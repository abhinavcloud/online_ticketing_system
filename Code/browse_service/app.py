import os
import json
import time
from typing import Any, Optional, List, Dict
import logging

import boto3
import psycopg2
import psycopg2.extras
from cachetools import TTLCache

try:
    import redis
except Exception:
    redis = None

from botocore.session import Session
from botocore.auth import SigV4QueryAuth
from botocore.awsrequest import AWSRequest

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Warm-container caches
_db_conn = None
_db_conn_refresh_at = 0

_valkey = None
_valkey_refresh_at = 0

_local = TTLCache(maxsize=1024, ttl=10)


# ---------------------------
# HTTP helpers
# ---------------------------
def response(status: int, body: Any):
    return {
        "statusCode": status,
        "headers": {
            "content-type": "application/json",
            "access-control-allow-origin": "*",
        },
        "body": json.dumps(body, default=str),
    }


def qsp(event: Dict[str, Any]) -> Dict[str, str]:
    return event.get("queryStringParameters") or {}


def method(event: Dict[str, Any]) -> str:
    return event.get("requestContext", {}).get("http", {}).get("method") or event.get("httpMethod", "")


def path(event: Dict[str, Any]) -> str:
    return (event.get("rawPath") or event.get("path") or "").rstrip("/")


# ---------------------------
# DB: IAM auth via RDS Proxy
# ---------------------------
def _db_token() -> str:
    """Generate IAM DB auth token used as password. [1](https://boto3.amazonaws.com/v1/documentation/api/1.28.3/reference/services/rds/client/generate_db_auth_token.html)[2](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.html)"""
    region = os.environ["AWS_REGION"]
    host = os.environ["DB_HOST"]
    port = int(os.environ.get("DB_PORT", "5432"))
    user = os.environ["DB_USER"]

    rds = boto3.client("rds", region_name=region)
    return rds.generate_db_auth_token(DBHostname=host, Port=port, DBUsername=user, Region=region)


def db_conn():
    """
    Reuse connection in warm container.
    Token lifetime is short; refresh before expiry. [2](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.html)
    """
    global _db_conn, _db_conn_refresh_at

    now = time.time()
    if _db_conn and now < _db_conn_refresh_at:
        return _db_conn

    conn = psycopg2.connect(
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", "5432")),
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=_db_token(),
        sslmode="require",
        connect_timeout=5,
        cursor_factory=psycopg2.extras.RealDictCursor,
    )
    conn.autocommit = True
    _db_conn = conn
    _db_conn_refresh_at = now + (14 * 60)  # refresh before 15 min window
    return conn


# ---------------------------
# Valkey/Redis: IAM auth
# ---------------------------
def _elasticache_iam_token(user_id: str, cache_name: str, region: str) -> str:
    """
    IAM token is a SigV4 presigned URL, used as password (without http://). [3](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/auth-iam.html)
    """
    cache_name = cache_name.lower()  # doc note about lowercase cache names [3](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/auth-iam.html)
    url = f"http://{cache_name}/"
    params = {"Action": "connect", "User": user_id, "ResourceType": "ServerlessCache"}

    aws_req = AWSRequest(method="GET", url=url, params=params)
    sess = Session()
    creds = sess.get_credentials().get_frozen_credentials()

    signer = SigV4QueryAuth(credentials=creds, service_name="elasticache", region_name=region, expires=900)
    signer.add_auth(aws_req)

    return aws_req.url.replace("http://", "")


def browse_cache():
    """
    Optional browse cache client. IAM auth requires TLS and userId==userName. [3](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/auth-iam.html)
    """
    global _valkey, _valkey_refresh_at

    if redis is None:
        return None

    endpoint = os.environ.get("BROWSE_CACHE_ENDPOINT")
    port = os.environ.get("BROWSE_CACHE_PORT")
    cache_name = os.environ.get("BROWSE_CACHE_NAME")
    user_id = os.environ.get("ELASTICACHE_USER_ID")

    if not (endpoint and port and cache_name and user_id):
        return None

    now = time.time()
    if _valkey and now < _valkey_refresh_at:
        return _valkey

    token = _elasticache_iam_token(user_id=user_id, cache_name=cache_name, region=os.environ["AWS_REGION"])

    client = redis.Redis(
        host=endpoint,
        port=int(port),
        username=user_id,          # IAM-enabled user id; must match username [3](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/auth-iam.html)
        password=token,            # SigV4 token used as password [3](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/auth-iam.html)
        ssl=True,                  # TLS required for IAM auth [3](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/auth-iam.html)
        ssl_cert_reqs=None,
        decode_responses=True,
        socket_connect_timeout=2,
        socket_timeout=2,
    )

    client.ping()
    _valkey = client
    _valkey_refresh_at = now + (14 * 60)
    return client


def cached_json(key: str, ttl: int, compute_fn):
    # 1) local warm cache
    if key in _local:
        return _local[key]

    # 2) distributed browse cache
    r = None
    try:
        r = browse_cache()
    except Exception as e:
        logger.warning("browse cache unavailable: %s", str(e))

    if r:
        try:
            v = r.get(key)
            if v:
                obj = json.loads(v)
                _local[key] = obj
                return obj
        except Exception as e:
            logger.warning("browse cache read failed: %s", str(e))

    # 3) compute + write back
    obj = compute_fn()
    _local[key] = obj

    if r:
        try:
            r.setex(key, ttl, json.dumps(obj, default=str))
        except Exception as e:
            logger.warning("browse cache write failed: %s", str(e))

    return obj


# ---------------------------
# Queries mapped to your API
# ---------------------------
def get_locations(conn, page: int, page_size: int):
    off = (page - 1) * page_size
    with conn.cursor() as cur:
        cur.execute("SELECT count(*) AS c FROM public.locations;")
        total = int(cur.fetchone()["c"])
        cur.execute(
            "SELECT id, name FROM public.locations ORDER BY name ASC LIMIT %s OFFSET %s;",
            (page_size, off),
        )
        rows = cur.fetchall()

    return {
        "page": page,
        "pageSize": page_size,
        "total": total,
        "locations": [{"locationId": str(r["id"]), "locationName": r["name"]} for r in rows],
    }


def get_venues(conn, location_id: str, page: int, page_size: int):
    off = (page - 1) * page_size
    with conn.cursor() as cur:
        cur.execute("SELECT count(*) AS c FROM public.venues WHERE location_id=%s;", (location_id,))
        total = int(cur.fetchone()["c"])
        cur.execute(
            """
            SELECT id, name
            FROM public.venues
            WHERE location_id=%s
            ORDER BY name ASC
            LIMIT %s OFFSET %s;
            """,
            (location_id, page_size, off),
        )
        rows = cur.fetchall()

    return {
        "page": page,
        "pageSize": page_size,
        "total": total,
        "venues": [{"venueId": str(r["id"]), "venueName": r["name"]} for r in rows],
    }


def get_performers(conn, location_id: str, page: int, page_size: int):
    """
    Your API: performers by location.
    We derive via events->venue->location and distinct performers.
    """
    off = (page - 1) * page_size
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT count(*) AS c
            FROM (
              SELECT DISTINCT p.id
              FROM public.performers p
              JOIN public.event_performers ep ON ep.performer_id = p.id
              JOIN public.events e ON e.id = ep.event_id
              JOIN public.venues v ON v.id = e.venue_id
              WHERE v.location_id = %s
            ) x;
            """,
            (location_id,),
        )
        total = int(cur.fetchone()["c"])

        cur.execute(
            """
            SELECT DISTINCT p.id, p.name
            FROM public.performers p
            JOIN public.event_performers ep ON ep.performer_id = p.id
            JOIN public.events e ON e.id = ep.event_id
            JOIN public.venues v ON v.id = e.venue_id
            WHERE v.location_id = %s
            ORDER BY p.name ASC
            LIMIT %s OFFSET %s;
            """,
            (location_id, page_size, off),
        )
        rows = cur.fetchall()

    return {
        "page": page,
        "pageSize": page_size,
        "total": total,
        "performers": [{"performerId": str(r["id"]), "performerName": r["name"]} for r in rows],
    }


def list_events(conn, location_id: str, performer_id: Optional[str], venue_id: Optional[str], page: int, page_size: int):
    off = (page - 1) * page_size

    filters = ["v.location_id = %s"]
    params: List[Any] = [location_id]

    if performer_id:
        filters.append("ep.performer_id = %s")
        params.append(performer_id)

    if venue_id:
        filters.append("v.id = %s")
        params.append(venue_id)

    where = " AND ".join(filters)

    with conn.cursor() as cur:
        # total
        cur.execute(
            f"""
            SELECT count(DISTINCT e.id) AS c
            FROM public.events e
            JOIN public.venues v ON v.id = e.venue_id
            LEFT JOIN public.event_performers ep ON ep.event_id = e.id
            WHERE {where};
            """,
            tuple(params),
        )
        total = int(cur.fetchone()["c"])

        # page data
        cur.execute(
            f"""
            SELECT DISTINCT e.id, e.name, e.event_date, e.event_type,
                   v.id AS venue_id, v.name AS venue_name,
                   l.id AS location_id, l.name AS location_name
            FROM public.events e
            JOIN public.venues v ON v.id = e.venue_id
            JOIN public.locations l ON l.id = v.location_id
            LEFT JOIN public.event_performers ep ON ep.event_id = e.id
            WHERE {where}
            ORDER BY e.event_date ASC
            LIMIT %s OFFSET %s;
            """,
            tuple(params + [page_size, off]),
        )
        events = cur.fetchall()

        # performers for returned events
        event_ids = [e["id"] for e in events]
        perf_map = {str(eid): [] for eid in event_ids}

        if event_ids:
            cur.execute(
                """
                SELECT ep.event_id, p.id AS performer_id, p.name AS performer_name
                FROM public.event_performers ep
                JOIN public.performers p ON p.id = ep.performer_id
                WHERE ep.event_id = ANY(%s);
                """,
                (event_ids,),
            )
            for r in cur.fetchall():
                perf_map[str(r["event_id"])].append(
                    {"performerId": str(r["performer_id"]), "performerName": r["performer_name"]}
                )

    return {
        "page": page,
        "pageSize": page_size,
        "total": total,
        "events": [
            {
                "eventId": str(e["id"]),
                "eventName": e["name"],
                "dateTime": e["event_date"].isoformat(),
                "category": e.get("event_type"),
                "location": {"locationId": str(e["location_id"]), "locationName": e["location_name"]},
                "venue": {"venueId": str(e["venue_id"]), "venueName": e["venue_name"]},
                "performers": perf_map.get(str(e["id"]), []),
            }
            for e in events
        ],
    }


def get_event_details(conn, event_id: str):
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT e.id, e.name, e.description, e.event_date, e.status,
                   l.id AS location_id, l.name AS location_name,
                   v.id AS venue_id, v.name AS venue_name
            FROM public.events e
            JOIN public.venues v ON v.id = e.venue_id
            JOIN public.locations l ON l.id = v.location_id
            WHERE e.id = %s;
            """,
            (event_id,),
        )
        e = cur.fetchone()
        if not e:
            return None

        # performers
        cur.execute(
            """
            SELECT p.id, p.name
            FROM public.event_performers ep
            JOIN public.performers p ON p.id = ep.performer_id
            WHERE ep.event_id = %s
            ORDER BY p.name ASC;
            """,
            (event_id,),
        )
        performers = [{"performerId": str(r["id"]), "performerName": r["name"]} for r in cur.fetchall()]

        # categories + total/available (computed from seats)
        cur.execute(
            """
            SELECT
              c.id AS category_id,
              c.name AS category_name,
              c.price,
              c.currency,
              COUNT(s.id) AS total_tickets,
              SUM(CASE WHEN s.status='AVAILABLE' THEN 1 ELSE 0 END) AS available_tickets
            FROM public.event_categories c
            LEFT JOIN public.seats s
              ON s.category_id = c.id AND s.event_id = c.event_id
            WHERE c.event_id = %s
            GROUP BY c.id, c.name, c.price, c.currency
            ORDER BY c.price DESC;
            """,
            (event_id,),
        )

        ticket_categories = []
        for r in cur.fetchall():
            available = int(r["available_tickets"] or 0)
            ticket_categories.append(
                {
                    "categoryId": str(r["category_id"]),
                    "categoryName": r["category_name"],
                    "price": int(r["price"]),
                    "currency": r["currency"],
                    "totalTickets": int(r["total_tickets"] or 0),
                    "availableTickets": available,
                    "status": "AVAILABLE" if available > 0 else "SOLD_OUT",
                }
            )

    return {
        "eventId": str(e["id"]),
        "eventName": e["name"],
        "eventDescription": e.get("description"),
        "dateTime": e["event_date"].isoformat(),
        "status": str(e["status"]),
        "location": {"locationId": str(e["location_id"]), "locationName": e["location_name"]},
        "venue": {"venueId": str(e["venue_id"]), "venueName": e["venue_name"]},
        "performers": performers,
        "ticketCategories": ticket_categories,
        "seatMap": {
            "applicable": True,
            "type": "RESERVED_SEATING",
            "seatEndpoint": f"/v1/events/{event_id}/seats",
        },
    }


# ---------------------------
# Lambda handler (routing)
# ---------------------------
def handler(event, context):
    try:
        conn = db_conn()
    except Exception as e:
        logger.exception("db connect failed")
        return response(500, {"error": "DB_CONNECTION_FAILED", "message": str(e)})

    p = path(event)
    m = method(event)
    qs = qsp(event)
    ttl = int(os.environ.get("BROWSE_CACHE_TTL_SECONDS", "30"))

    # GET /v1/location
    if m == "GET" and p == "/v1/location":
        page = int(qs.get("page", "1"))
        page_size = int(qs.get("pageSize", "10"))
        key = f"browse:locations:p={page}:s={page_size}"
        return response(200, cached_json(key, ttl, lambda: get_locations(conn, page, page_size)))

    # GET /v1/venue?location=...
    if m == "GET" and p == "/v1/venue":
        location_id = qs.get("location")
        if not location_id:
            return response(400, {"error": "MISSING_LOCATION"})
        page = int(qs.get("page", "1"))
        page_size = int(qs.get("pageSize", "10"))
        key = f"browse:venues:loc={location_id}:p={page}:s={page_size}"
        return response(200, cached_json(key, ttl, lambda: get_venues(conn, location_id, page, page_size)))

    # GET /v1/performers?location=...
    if m == "GET" and p == "/v1/performers":
        location_id = qs.get("location")
        if not location_id:
            return response(400, {"error": "MISSING_LOCATION"})
        page = int(qs.get("page", "1"))
        page_size = int(qs.get("pageSize", "10"))
        key = f"browse:performers:loc={location_id}:p={page}:s={page_size}"
        return response(200, cached_json(key, ttl, lambda: get_performers(conn, location_id, page, page_size)))

    # GET /v1/events?location=...&performer=...&venue=...
    if m == "GET" and p == "/v1/events":
        location_id = qs.get("location")
        if not location_id:
            return response(400, {"error": "MISSING_LOCATION"})
        performer_id = qs.get("performer")
        venue_id = qs.get("venue")
        page = int(qs.get("page", "1"))
        page_size = int(qs.get("pageSize", "20"))

        key = f"browse:events:loc={location_id}:perf={performer_id}:venue={venue_id}:p={page}:s={page_size}"
        return response(
            200,
            cached_json(
                key,
                ttl,
                lambda: list_events(conn, location_id, performer_id, venue_id, page, page_size),
            ),
        )

    # GET /v1/event/{eventId}
    if m == "GET" and p.startswith("/v1/event/"):
        event_id = p.split("/v1/event/", 1)[1]
        key = f"browse:event:{event_id}"
        data = cached_json(key, ttl, lambda: get_event_details(conn, event_id))
        if not data:
            return response(404, {"error": "EVENT_NOT_FOUND"})
        return response(200, data)

    return response(404, {"error": "NOT_FOUND", "path": p, "method": m})
