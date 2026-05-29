import os
import json
import time
import logging
from typing import Any, Optional, Callable

import boto3
import psycopg2
import psycopg2.extras
from cachetools import TTLCache

try:
    import redis  # redis-py
except Exception:  # pragma: no cover
    redis = None

from botocore.session import Session
from botocore.auth import SigV4QueryAuth
from botocore.awsrequest import AWSRequest

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ------------------------------------------------------------
# Warm-container caches (persist for same Lambda execution env)
# ------------------------------------------------------------
_DB_CONN = None
_DB_REFRESH_AT = 0.0

_VALKEY = None
_VALKEY_REFRESH_AT = 0.0

# Small local cache for hot keys within the same warm container
_LOCAL_CACHE = TTLCache(maxsize=1024, ttl=10)


# ----------------------------
# HTTP helpers
# ----------------------------

def _json_response(status_code: int, body: Any) -> dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {
            "content-type": "application/json",
            "access-control-allow-origin": "*",
        },
        "body": json.dumps(body, default=str),
    }


def _http_method(event: dict[str, Any]) -> str:
    # HTTP API (v2)
    m = event.get("requestContext", {}).get("http", {}).get("method")
    if m:
        return m
    # REST API (v1)
    return event.get("httpMethod", "")


def _http_path(event: dict[str, Any]) -> str:
    # HTTP API (v2)
    p = event.get("rawPath")
    if p:
        return p.rstrip("/")
    # REST API (v1)
    return (event.get("path") or "").rstrip("/")


def _query_params(event: dict[str, Any]) -> dict[str, str]:
    return event.get("queryStringParameters") or {}


def _path_params(event: dict[str, Any]) -> dict[str, str]:
    return event.get("pathParameters") or {}


def _safe_int(s: Optional[str], default: int) -> int:
    try:
        return int(s) if s is not None else default
    except Exception:
        return default


# ----------------------------
# DB: IAM auth via RDS Proxy
# ----------------------------

def _db_auth_token() -> str:
    """Generate IAM DB auth token used as the password."""
    region = os.environ["APP_REGION"]
    host = os.environ["DB_HOST"]
    port = int(os.environ.get("DB_PORT", "5432"))
    user = os.environ["DB_USER"]

    rds = boto3.client("rds", region_name=region)
    return rds.generate_db_auth_token(DBHostname=host, Port=port, DBUsername=user, Region=region)


def _db_conn():
    """Re-use a DB connection within the warm Lambda container."""
    global _DB_CONN, _DB_REFRESH_AT

    now = time.time()
    if _DB_CONN is not None and now < _DB_REFRESH_AT:
        try:
            # Validate connectivity with a lightweight query
            with _DB_CONN.cursor() as test.cur:
                test.cur.execute("SELECT 1;")
                cur.fetchone()
            return _DB_CONN
        except (psycopg2.OperationalError, psycopg2.InterfaceError) as e:
            print("DB connection failed health check, refreshing: %s", str(e))

    conn = psycopg2.connect(
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", "5432")),
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=_db_auth_token(),
        sslmode="require",
        connect_timeout=5,
        cursor_factory=psycopg2.extras.RealDictCursor,
    )
    conn.autocommit = True

    _DB_CONN = conn
    # IAM token is valid 15 minutes; refresh earlier
    _DB_REFRESH_AT = now + (14 * 60)
    return conn


# ----------------------------
# ElastiCache Serverless (Valkey/Redis): IAM auth
# ----------------------------

def _elasticache_iam_token(user_id: str, cache_name: str, region: str) -> str:
    """Generate SigV4 presigned URL token used as Redis password (without http://)."""
    cache_name = cache_name.lower()

    # Request: http://{cache_name}/?Action=connect&User={user_id}&ResourceType=ServerlessCache
    url = f"http://{cache_name}/"
    params = {"Action": "connect", "User": user_id, "ResourceType": "ServerlessCache"}

    aws_req = AWSRequest(method="GET", url=url, params=params)
    sess = Session()
    creds = sess.get_credentials().get_frozen_credentials()

    signer = SigV4QueryAuth(
        credentials=creds,
        service_name="elasticache",
        region_name=region,
        expires=900,
    )
    signer.add_auth(aws_req)

    return aws_req.url.replace("http://", "")


def _browse_cache_client():
    """Optional Valkey client. Returns None if env vars are missing."""
    global _VALKEY, _VALKEY_REFRESH_AT

    if redis is None:
        return None

    endpoint = os.environ.get("BROWSE_CACHE_ENDPOINT")
    port = os.environ.get("BROWSE_CACHE_PORT")
    cache_name = os.environ.get("BROWSE_CACHE_NAME")
    user_id = os.environ.get("ELASTICACHE_USER_ID")

    if not (endpoint and port and cache_name and user_id):
        return None

    now = time.time()
    if _VALKEY is not None and now < _VALKEY_REFRESH_AT:
        return _VALKEY

    token = _elasticache_iam_token(user_id=user_id, cache_name=cache_name, region=os.environ["APP_REGION"])

    client = redis.Redis(
        host=endpoint,
        port=int(port),
        username=user_id,
        password=token,
        ssl=True,
        ssl_cert_reqs=None,
        decode_responses=True,
        socket_connect_timeout=2,
        socket_timeout=2,
    )

    # Validate connectivity
    client.ping()

    _VALKEY = client
    _VALKEY_REFRESH_AT = now + (14 * 60)
    return client


def _cached_json(key: str, ttl_seconds: int, compute_fn: Callable[[], Any]) -> Any:
    # 1) Local warm cache
    if key in _LOCAL_CACHE:
        return _LOCAL_CACHE[key]

    # 2) Distributed browse cache (optional)
    client = None
    try:
        client = _browse_cache_client()
    except Exception as e:
        logger.warning("browse cache unavailable: %s", str(e))

    if client:
        try:
            raw = client.get(key)
            if raw is not None:
                obj = json.loads(raw)
                _LOCAL_CACHE[key] = obj
                return obj
        except Exception as e:
            logger.warning("browse cache read failed: %s", str(e))

    # 3) Compute + write-back
    obj = compute_fn()
    _LOCAL_CACHE[key] = obj

    if client:
        try:
            client.setex(key, ttl_seconds, json.dumps(obj, default=str))
        except Exception as e:
            logger.warning("browse cache write failed: %s", str(e))

    return obj


# ----------------------------
# SQL: API mappings
# ----------------------------

def _get_locations(conn, page: int, page_size: int) -> dict[str, Any]:
    offset = (page - 1) * page_size
    with conn.cursor() as cur:
        cur.execute("SELECT count(*) AS c FROM public.locations;")
        total = int(cur.fetchone()["c"])
        cur.execute(
            "SELECT id, name FROM public.locations ORDER BY name ASC LIMIT %s OFFSET %s;",
            (page_size, offset),
        )
        rows = cur.fetchall()

    return {
        "page": page,
        "pageSize": page_size,
        "total": total,
        "locations": [{"locationId": str(r["id"]), "locationName": r["name"]} for r in rows],
    }


def _get_venues(conn, location_id: str, page: int, page_size: int) -> dict[str, Any]:
    offset = (page - 1) * page_size
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
            (location_id, page_size, offset),
        )
        rows = cur.fetchall()

    return {
        "page": page,
        "pageSize": page_size,
        "total": total,
        "venues": [{"venueId": str(r["id"]), "venueName": r["name"]} for r in rows],
    }


def _get_performers(conn, location_id: str, page: int, page_size: int) -> dict[str, Any]:
    offset = (page - 1) * page_size
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
            (location_id, page_size, offset),
        )
        rows = cur.fetchall()

    return {
        "page": page,
        "pageSize": page_size,
        "total": total,
        "performers": [{"performerId": str(r["id"]), "performerName": r["name"]} for r in rows],
    }


def _list_events(
    conn,
    location_id: str,
    performer_id: Optional[str],
    venue_id: Optional[str],
    page: int,
    page_size: int,
) -> dict[str, Any]:
    offset = (page - 1) * page_size

    filters = ["v.location_id = %s"]
    params: list[Any] = [location_id]

    if performer_id:
        filters.append("ep.performer_id = %s")
        params.append(performer_id)

    if venue_id:
        filters.append("v.id = %s")
        params.append(venue_id)

    where = " AND ".join(filters)

    with conn.cursor() as cur:
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

        cur.execute(
            f"""
            SELECT DISTINCT
              e.id, e.name, e.event_date, e.event_type,
              l.id AS location_id, l.name AS location_name,
              v.id AS venue_id, v.name AS venue_name
            FROM public.events e
            JOIN public.venues v ON v.id = e.venue_id
            JOIN public.locations l ON l.id = v.location_id
            LEFT JOIN public.event_performers ep ON ep.event_id = e.id
            WHERE {where}
            ORDER BY e.event_date ASC
            LIMIT %s OFFSET %s;
            """,
            tuple(params + [page_size, offset]),
        )
        events = cur.fetchall()

        event_ids = [e["id"] for e in events]
        perfs_by_event: dict[str, list[dict[str, str]]] = {str(eid): [] for eid in event_ids}

        if event_ids:
            cur.execute(
                """
                SELECT ep.event_id, p.id AS performer_id, p.name AS performer_name
                FROM public.event_performers ep
                JOIN public.performers p ON p.id = ep.performer_id
                WHERE ep.event_id = ANY(%s::uuid[]);
                """,
                (event_ids,),
            )
            for r in cur.fetchall():
                perfs_by_event[str(r["event_id"])].append(
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
                "performers": perfs_by_event.get(str(e["id"]), []),
            }
            for e in events
        ],
    }


def _event_details(conn, event_id: str) -> Optional[dict[str, Any]]:
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

        # ticketCategories computed from event_categories + seats
        cur.execute(
            """
            SELECT
              c.id AS category_id,
              c.name AS category_name,
              c.price AS price,
              c.currency AS currency,
              COUNT(s.id) AS total_tickets,
              SUM(CASE WHEN s.status='AVAILABLE' THEN 1 ELSE 0 END) AS available_tickets
            FROM public.event_categories c
            LEFT JOIN public.seats s
              ON s.event_id = c.event_id AND s.category_id = c.id
            WHERE c.event_id = %s
            GROUP BY c.id, c.name, c.price, c.currency
            ORDER BY c.price DESC;
            """,
            (event_id,),
        )

        categories = []
        for r in cur.fetchall():
            available = int(r["available_tickets"] or 0)
            categories.append(
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
        "ticketCategories": categories,
        "seatMap": {
            "applicable": True,
            "type": "RESERVED_SEATING",
            "seatEndpoint": f"/v1/events/{event_id}/seats",
        },
    }


# ----------------------------
# Lambda handler
# ----------------------------

def handler(event: dict[str, Any], context: Any):
    p = _http_path(event)
    m = _http_method(event)
    qs = _query_params(event)

    ttl = _safe_int(os.environ.get("BROWSE_CACHE_TTL_SECONDS"), 30)

    try:
        conn = _db_conn()
    except Exception as e:
        logger.exception("DB connect failed")
        return _json_response(500, {"error": "DB_CONNECTION_FAILED", "message": str(e)})

    # GET /v1/location
    if m == "GET" and p == "/v1/location":
        page = _safe_int(qs.get("page"), 1)
        page_size = _safe_int(qs.get("pageSize"), 10)
        key = f"browse:locations:p={page}:s={page_size}"
        data = _cached_json(key, ttl, lambda: _get_locations(conn, page, page_size))
        return _json_response(200, data)

    # GET /v1/venue?location=<location_id>
    if m == "GET" and p == "/v1/venue":
        location_id = qs.get("location")
        if not location_id:
            return _json_response(400, {"error": "MISSING_LOCATION"})
        page = _safe_int(qs.get("page"), 1)
        page_size = _safe_int(qs.get("pageSize"), 10)
        key = f"browse:venues:loc={location_id}:p={page}:s={page_size}"
        data = _cached_json(key, ttl, lambda: _get_venues(conn, location_id, page, page_size))
        return _json_response(200, data)

    # GET /v1/performers?location=<location_id>
    if m == "GET" and p == "/v1/performers":
        location_id = qs.get("location")
        if not location_id:
            return _json_response(400, {"error": "MISSING_LOCATION"})
        page = _safe_int(qs.get("page"), 1)
        page_size = _safe_int(qs.get("pageSize"), 10)
        key = f"browse:performers:loc={location_id}:p={page}:s={page_size}"
        data = _cached_json(key, ttl, lambda: _get_performers(conn, location_id, page, page_size))
        return _json_response(200, data)

    # GET /v1/events?location=<location_id>&performer=<performer_id>&venue=<venue_id>
    if m == "GET" and p == "/v1/events":
        location_id = qs.get("location")
        if not location_id:
            return _json_response(400, {"error": "MISSING_LOCATION"})
        performer_id = qs.get("performer")
        venue_id = qs.get("venue")
        page = _safe_int(qs.get("page"), 1)
        page_size = _safe_int(qs.get("pageSize"), 20)

        key = f"browse:events:loc={location_id}:perf={performer_id}:venue={venue_id}:p={page}:s={page_size}"
        data = _cached_json(key, ttl, lambda: _list_events(conn, location_id, performer_id, venue_id, page, page_size))
        return _json_response(200, data)

    # GET /v1/event_detail/{eventId}
    if m == "GET" and p.startswith("/v1/event_detail/"):
        event_id = p.split("/v1/event_detail/", 1)[1]
        if not event_id:
            return _json_response(400, {"error": "MISSING_EVENT_ID"})
        key = f"browse:event:{event_id}"
        data = _cached_json(key, ttl, lambda: _event_details(conn, event_id))
        if not data:
            return _json_response(404, {"error": "EVENT_NOT_FOUND"})
        return _json_response(200, data)

    return _json_response(404, {"error": "NOT_FOUND", "path": p, "method": m})
