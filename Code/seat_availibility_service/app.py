import os
import json
import time
import base64
import logging
from typing import Any, Dict, Optional, List

import boto3

try:
    import redis  # redis-py (works with Valkey protocol)
except Exception:  # pragma: no cover
    redis = None

try:
    import psycopg2  # psycopg2-binary
except Exception:  # pragma: no cover
    psycopg2 = None

from botocore.session import Session
from botocore.auth import SigV4QueryAuth
from botocore.awsrequest import AWSRequest
from botocore.config import Config

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Fail fast to avoid long hangs
_BOTO_CFG = Config(connect_timeout=45, read_timeout=3, retries={"max_attempts": 1})

# ----------------------------
# Warm caches
# ----------------------------
_QUEUE_REDIS = None
_QUEUE_REDIS_REFRESH_AT = 0.0

_SEATLOCK_REDIS = None
_SEATLOCK_REDIS_REFRESH_AT = 0.0

_DB_CONN = None
_DB_CONN_REFRESH_AT = 0.0

_RDS_IAM_TOKEN = None
_RDS_IAM_TOKEN_REFRESH_AT = 0.0


# ----------------------------
# Utilities
# ----------------------------

def _resp(status_code: int, body: Any) -> Dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {
            "content-type": "application/json",
            "access-control-allow-origin": "*",
        },
        "body": json.dumps(body, default=str),
    }


def _get_user_sub_from_rest_api(event: Dict[str, Any]) -> Optional[str]:
    """REST API + Cognito Authorizer (proxy integration): event.requestContext.authorizer.claims"""
    rc = event.get("requestContext") or {}
    auth = rc.get("authorizer") or {}
    claims = auth.get("claims") or {}
    return claims.get("sub")


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, str(default)))
    except Exception:
        return default


def _env_bool(name: str, default: bool = False) -> bool:
    v = os.environ.get(name)
    if v is None:
        return default
    return str(v).strip().lower() in ("1", "true", "yes", "y")


def _env_str(primary: str, fallback: Optional[str] = None, required: bool = False) -> Optional[str]:
    v = os.environ.get(primary)
    if v is None and fallback:
        v = os.environ.get(fallback)
    if required and not v:
        raise KeyError(
            f"Missing required env var: {primary}" + (f" (or {fallback})" if fallback else "")
        )
    return v


def _headers_lc(event: Dict[str, Any]) -> Dict[str, str]:
    h = event.get("headers") or {}
    return {str(k).lower(): str(v) for k, v in h.items()}


def _b64url_decode(s: str) -> bytes:
    pad = "=" * (-len(s) % 4)
    return base64.urlsafe_b64decode(s + pad)


# ----------------------------
# ElastiCache Serverless IAM auth (Valkey)
# ----------------------------

def _elasticache_iam_token(user_id: str, cache_name: str, region: str) -> str:
    """Build a SigV4 presigned URL used as password for ElastiCache Serverless IAM auth (TLS required)."""
    cache_name = cache_name.lower()
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


def _queue_cache():
    """Queue cache (Valkey).

    Supports both QUEUE_CACHE_* and ACTIVE_USERS_CACHE_* env names.
    """
    global _QUEUE_REDIS, _QUEUE_REDIS_REFRESH_AT

    if redis is None:
        raise RuntimeError("redis library not available. Add redis to your Lambda layer/package.")

    endpoint = _env_str("QUEUE_CACHE_ENDPOINT", "ACTIVE_USERS_CACHE_ENDPOINT", required=True)
    port = int(_env_str("QUEUE_CACHE_PORT", "ACTIVE_USERS_CACHE_PORT") or "6379")
    cache_name = _env_str("QUEUE_CACHE_NAME", "ACTIVE_USERS_CACHE_NAME", required=True)
    user_id = _env_str("QUEUE_ELASTICACHE_USER_ID", "ELASTICACHE_USER_ID", required=True)
    region = os.environ.get("APP_REGION") or os.environ.get("AWS_DEFAULT_REGION")

    now = time.time()
    if _QUEUE_REDIS is not None and _QUEUE_REDIS.closed == 0 and now < _QUEUE_REDIS_REFRESH_AT:
        return _QUEUE_REDIS

    token = _elasticache_iam_token(user_id=user_id, cache_name=cache_name, region=region)

    client = redis.Redis(
        host=endpoint,
        port=port,
        username=user_id,
        password=token,
        ssl=True,
        ssl_cert_reqs=None,
        decode_responses=True,
        socket_connect_timeout=2,
        socket_timeout=2,
    )
    client.ping()

    _QUEUE_REDIS = client
    _QUEUE_REDIS_REFRESH_AT = now + (14 * 60)
    return client


def _seatlock_cache():
    """Seat lock cache (Valkey).

    Reservation service will write locks here.
    """
    global _SEATLOCK_REDIS, _SEATLOCK_REDIS_REFRESH_AT

    if redis is None:
        raise RuntimeError("redis library not available. Add redis to your Lambda layer/package.")

    endpoint = _env_str("SEAT_LOCK_CACHE_ENDPOINT", required=True)
    port = int(_env_str("SEAT_LOCK_CACHE_PORT") or "6379")
    cache_name = _env_str("SEAT_LOCK_CACHE_NAME", required=True)
    user_id = _env_str("SEAT_LOCK_ELASTICACHE_USER_ID", "ELASTICACHE_USER_ID", required=True)
    region = os.environ.get("APP_REGION") or os.environ.get("AWS_DEFAULT_REGION")

    now = time.time()
    if _SEATLOCK_REDIS is not None and _SEATLOCK_REDIS.closed == 0 and now < _SEATLOCK_REDIS_REFRESH_AT:
        return _SEATLOCK_REDIS

    token = _elasticache_iam_token(user_id=user_id, cache_name=cache_name, region=region)

    client = redis.Redis(
        host=endpoint,
        port=port,
        username=user_id,
        password=token,
        ssl=True,
        ssl_cert_reqs=None,
        decode_responses=True,
        socket_connect_timeout=2,
        socket_timeout=2,
    )
    client.ping()

    _SEATLOCK_REDIS = client
    _SEATLOCK_REDIS_REFRESH_AT = now + (14 * 60)
    return client


# ----------------------------
# Aurora Cluster + IAM DB Authentication
# ----------------------------

def _rds_iam_token(host: str, port: int, user: str, region: str) -> str:
    global _RDS_IAM_TOKEN, _RDS_IAM_TOKEN_REFRESH_AT

    now = time.time()
    refresh_seconds = int(os.environ.get("DB_IAM_TOKEN_REFRESH_SECONDS", "840"))  # 14 minutes

    if _RDS_IAM_TOKEN is not None and now < _RDS_IAM_TOKEN_REFRESH_AT:
        return _RDS_IAM_TOKEN

    rds = boto3.client("rds", config=_BOTO_CFG)
    token = rds.generate_db_auth_token(DBHostname=host, Port=port, DBUsername=user, Region=region)

    _RDS_IAM_TOKEN = token
    _RDS_IAM_TOKEN_REFRESH_AT = now + refresh_seconds
    return token


def _db_conn():
    global _DB_CONN, _DB_CONN_REFRESH_AT

    if psycopg2 is None:
        raise RuntimeError("psycopg2 not available. Add psycopg2-binary to your Lambda layer/package.")

    now = time.time()
    if _DB_CONN is not None and now < _DB_CONN_REFRESH_AT:
        try:
            # Validate connectivity with a lightweight query
            with _DB_CONN.cursor() as cur:
                cur.execute("SELECT 1;")
                cur.fetchone()
            return _DB_CONN
        except (psycopg2.OperationalError, psycopg2.InterfaceError) as e:
            print("DB connection failed health check, refreshing: %s", str(e))
            _DB_CONN = None  # Force refresh on next attempt

    db_host = os.environ["DB_HOST"]
    db_port = int(os.environ.get("DB_PORT", "5432"))
    db_name = os.environ["DB_NAME"]
    db_user = os.environ["DB_USER"]
    db_region = os.environ.get("DB_REGION") or os.environ.get("APP_REGION") or os.environ.get("AWS_DEFAULT_REGION")
    sslmode = os.environ.get("DB_SSLMODE", "require")

    token = _rds_iam_token(host=db_host, port=db_port, user=db_user, region=db_region)

    conn = psycopg2.connect(
        host=db_host,
        port=db_port,
        dbname=db_name,
        user=db_user,
        password=token,
        sslmode=sslmode,
        connect_timeout=45,
    )
    conn.autocommit = True

    _DB_CONN = conn
    _DB_CONN_REFRESH_AT = now + (8 * 60)
    return conn


# ----------------------------
# Booking token verification (KMS Verify)
# ----------------------------

def _verify_booking_token(token: str) -> Dict[str, Any]:
    parts = token.split(".")
    if len(parts) != 3:
        raise ValueError("Invalid token format")

    header_b64, payload_b64, sig_b64 = parts
    signing_input = f"{header_b64}.{payload_b64}".encode("utf-8")
    signature = _b64url_decode(sig_b64)

    payload = json.loads(_b64url_decode(payload_b64).decode("utf-8"))

    issuer_expected = os.environ.get("JWT_ISSUER", "ticketing-queue")
    now = int(time.time())
    if payload.get("iss") != issuer_expected:
        raise ValueError("Invalid issuer")
    if int(payload.get("exp", 0)) < now:
        raise ValueError("Token expired")

    kms = boto3.client("kms", config=_BOTO_CFG)
    kms.verify(
        KeyId=os.environ["JWT_KMS_KEY_ID"],
        Message=signing_input,
        MessageType="RAW",
        Signature=signature,
        SigningAlgorithm="RSASSA_PKCS1_V1_5_SHA_256",
    )

    return payload


# ----------------------------
# Key helpers (cluster-safe using hash-tag)
# ----------------------------

def _tag(event_id: str, category_id: str) -> str:
    return f"{{{event_id}:{category_id}}}"


def _queue_allowed_key(event_id: str, category_id: str) -> str:
    tag = _tag(event_id, category_id)
    return f"queue:{tag}:allowed"


def _seat_lock_key(event_id: str, category_id: str, seat_id: str) -> str:
    """Reservation service MUST write locks using this exact key format.

    This format is required so the seat availability service can MGET many keys
    without CROSSSLOT errors in Valkey cluster mode.
    """
    tag = _tag(event_id, category_id)
    return f"seatlock:{tag}:{seat_id}"


# ----------------------------
# DB query: fetch seat map
# ----------------------------

def _fetch_seats_from_db(event_id: str, category_id: str, limit: int) -> List[Dict[str, Any]]:
    """Return all seats for event+category, including AVAILABLE and BOOKED.

    Expected schema columns: seats(event_id, category_id, seat_label,  status)
    """
    global _DB_CONN, _DB_CONN_REFRESH_AT

    sql = """
        SELECT seat_label, status
        FROM seats
        WHERE event_id = %s
          AND category_id = %s
        ORDER BY seat_label
        LIMIT %s
    """

    for attempt in range(2):
        try:
            conn = _db_conn()
            with conn.cursor() as cur:
                cur.execute(sql, (event_id, category_id, limit))
                rows = cur.fetchall()
            out = []
            for r in rows:
                out.append({
                    "seatId": r[0],
                    "status": r[1],  # AVAILABLE or BOOKED (DB truth)
                })
            return out
        except psycopg2.OperationalError:
            if attempt == 0:
                _DB_CONN = None
                _DB_CONN_REFRESH_AT = 0.0
            else:
                raise


# ----------------------------
# Handler
# ----------------------------

def handle_get_seats(event, context):
    user_sub = _get_user_sub_from_rest_api(event)
    if not user_sub:
        return _resp(401, {"error": "UNAUTHORIZED"})

    # REST API: pathParameters + queryStringParameters
    path_params = event.get("pathParameters") or {}
    event_id = path_params.get("eventId")
    qs = event.get("queryStringParameters") or {}
    category_id = qs.get("category_id")

    if not event_id or not category_id:
        return _resp(400, {"error": "VALIDATION_ERROR", "message": "eventId and category_id are required"})

    # bookingToken is required because only ALLOWED users can view seat map
    h = _headers_lc(event)
    booking_token = h.get("x-booking-token")
    if not booking_token:
        return _resp(400, {"error": "MISSING_BOOKING_TOKEN", "message": "x-booking-token header required"})

    # verify token and enforce scope
    try:
        bt = _verify_booking_token(booking_token)
    except Exception as e:
        return _resp(401, {"error": "INVALID_BOOKING_TOKEN", "message": str(e)})

    if bt.get("sub") != user_sub:
        return _resp(403, {"error": "TOKEN_USER_MISMATCH"})
    if bt.get("eventId") != event_id or bt.get("categoryId") != category_id:
        return _resp(403, {"error": "TOKEN_SCOPE_MISMATCH"})

    session_id = bt.get("sessionId")
    if not session_id:
        return _resp(401, {"error": "INVALID_BOOKING_TOKEN", "message": "sessionId missing"})

    # CHANGED: reject tokens not scoped for queue booking
    if bt.get("scope") != "booking:queue":
        return _resp(401, {"error": "INVALID_BOOKING_TOKEN", "message": "invalid token scope"})

    # Ensure session is currently ALLOWED (queue cache)
    try:
        q = _queue_cache()
        allowed_key = _queue_allowed_key(event_id, category_id)
        if not q.sismember(allowed_key, session_id):
            return _resp(200, {
                "eventId": event_id,
                "categoryId": category_id,
                # CHANGED: use time.gmtime() to guarantee UTC; %z is unreliable on some Python builds
                "asOf": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "seats": [],
                "status": "WAITING",
                "message": "You are not admitted yet. Please poll and try again."
            })
    except Exception as e:
        logger.exception("Queue cache check failed")
        return _resp(500, {"error": "QUEUE_CACHE_FAILED", "message": str(e)})

    # Get seat map from DB (AVAILABLE / BOOKED)
    limit = _env_int("SEATS_PAGE_SIZE", 200)
    try:
        seats = _fetch_seats_from_db(event_id, category_id, limit)
    except Exception as e:
        logger.exception("DB seats query failed")
        return _resp(500, {"error": "DB_QUERY_FAILED", "message": str(e)})

    # Overlay LOCKED status from seat-lock cache (written by Reservation service)
    show_lock_expiry = _env_bool("SHOW_LOCK_EXPIRES_AT", default=False)

    try:
        sl = _seatlock_cache()
        # Build lock keys for each seat. All keys share same hash tag -> safe for MGET in cluster mode.
        lock_keys = [_seat_lock_key(event_id, category_id, s["seatId"]) for s in seats]
        lock_vals = sl.mget(lock_keys) if lock_keys else []

        # CHANGED: batch all pttl calls into a single pipeline to avoid N sequential
        # round trips when show_lock_expiry is enabled.
        lock_ttls = {}
        if show_lock_expiry and lock_vals:
            locked_indices = [i for i, v in enumerate(lock_vals) if v is not None]
            if locked_indices:
                pipe = sl.pipeline(transaction=False)
                for i in locked_indices:
                    pipe.pttl(lock_keys[i])
                lock_ttls = dict(zip(locked_indices, pipe.execute()))

        for idx, s in enumerate(seats):
            # Only overlay LOCKED if seat is AVAILABLE in DB
            if s.get("status") == "AVAILABLE" and lock_vals and lock_vals[idx] is not None:
                s["status"] = "LOCKED"
                if show_lock_expiry:
                    ttl_ms = lock_ttls.get(idx)
                    if ttl_ms and ttl_ms > 0:
                        # CHANGED: use time.gmtime() for UTC; time.localtime() is not
                        # guaranteed UTC and %z can be empty on some Python builds
                        s["lockExpiresAt"] = time.strftime(
                            "%Y-%m-%dT%H:%M:%SZ",
                            time.gmtime(time.time() + (ttl_ms / 1000.0)),
                        )

    except Exception as e:
        logger.exception("Seat-lock cache check failed")
        return _resp(500, {"error": "SEAT_LOCK_CACHE_FAILED", "message": str(e)})

    return _resp(200, {
        "eventId": event_id,
        "categoryId": category_id,
        # CHANGED: use time.gmtime() to guarantee UTC; %z is unreliable on some Python builds
        "asOf": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "seats": seats,
        # CHANGED: signal to the client when the result was truncated by SEATS_PAGE_SIZE
        "hasMore": len(seats) == limit,
    })


def handler(event, context):
    resource = (event.get("resource") or "").lower()
    path = (event.get("path") or "").lower()
    method = (event.get("httpMethod") or "").upper()

    # GET /v1/event/{eventId}/seats?category_id=...
    if method == "GET" and (resource.endswith("/v1/event/{eventid}/seats") or path.endswith("/seats")):
        return handle_get_seats(event, context)

    return _resp(404, {"error": "NOT_FOUND", "message": f"Unsupported route {method} {path}"})