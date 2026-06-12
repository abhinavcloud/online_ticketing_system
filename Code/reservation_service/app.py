import os
import json
import time
import uuid
import base64
import logging
from typing import Any, Dict, Optional, List, Tuple

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


def _parse_json_body(event: Dict[str, Any]) -> Dict[str, Any]:
    raw = event.get("body") or ""
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode("utf-8")
    if not raw:
        return {}
    return json.loads(raw)


def _headers_lc(event: Dict[str, Any]) -> Dict[str, str]:
    h = event.get("headers") or {}
    return {str(k).lower(): str(v) for k, v in h.items()}


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


def _env_str(primary: str, fallback: Optional[str] = None, required: bool = False) -> Optional[str]:
    v = os.environ.get(primary)
    if v is None and fallback:
        v = os.environ.get(fallback)
    if required and not v:
        raise KeyError(
            f"Missing required env var: {primary}" + (f" (or {fallback})" if fallback else "")
        )
    return v


def _b64url_decode(s: str) -> bytes:
    pad = "=" * (-len(s) % 4)
    return base64.urlsafe_b64decode(s + pad)


# ----------------------------
# Booking token verification (KMS Verify)
# ----------------------------

def _verify_booking_token(token: str) -> Dict[str, Any]:
    """Verify the Queue-issued bookingToken JWT using KMS Verify.

    Expects RSASSA_PKCS1_V1_5_SHA_256 signatures (RS256-like).
    """
    parts = token.split(".")
    if len(parts) != 3:
        raise ValueError("Invalid bookingToken format")

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

    verify_resp = kms.verify(
        KeyId=os.environ["JWT_KMS_KEY_ID"],
        Message=signing_input,
        MessageType="RAW",
        Signature=signature,
        SigningAlgorithm="RSASSA_PKCS1_V1_5_SHA_256",
    )
    
    if not verify_resp.get("SignatureValid"):
        raise ValueError("Invalid signature")

    return payload


# ----------------------------
# ElastiCache Serverless IAM auth (Valkey)
# ----------------------------

def _elasticache_iam_token(user_id: str, cache_name: str, region: str) -> str:
    """SigV4 presigned URL used as password for ElastiCache Serverless IAM auth (TLS required)."""
    cache_name = cache_name.lower()
    url = f"http://{cache_name}/"
    params = {"Action": "connect", "User": user_id}

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
    """Cache A: Queue cache (same as your queue service)."""
    global _QUEUE_REDIS, _QUEUE_REDIS_REFRESH_AT

    if redis is None:
        raise RuntimeError("redis library not available. Add redis to your Lambda layer/package.")

    endpoint = _env_str("QUEUE_CACHE_ENDPOINT", "ACTIVE_USERS_CACHE_ENDPOINT", required=True)
    port = int(_env_str("QUEUE_CACHE_PORT", "ACTIVE_USERS_CACHE_PORT") or "6379")
    cache_name = _env_str("QUEUE_CACHE_NAME", "ACTIVE_USERS_CACHE_NAME", required=True)
    user_id = _env_str("QUEUE_ELASTICACHE_USER_ID", "ELASTICACHE_USER_ID", required=True)
    region = os.environ.get("APP_REGION") or os.environ.get("AWS_DEFAULT_REGION")

    now = time.time()
    if _QUEUE_REDIS is not None and now < _QUEUE_REDIS_REFRESH_AT:
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
    """Cache B: Seat-lock cache (Valkey). Locks are written here."""
    global _SEATLOCK_REDIS, _SEATLOCK_REDIS_REFRESH_AT

    if redis is None:
        raise RuntimeError("redis library not available. Add redis to your Lambda layer/package.")

    endpoint = _env_str("SEAT_LOCK_CACHE_ENDPOINT", required=True)
    port = int(_env_str("SEAT_LOCK_CACHE_PORT") or "6379")
    cache_name = _env_str("SEAT_LOCK_CACHE_NAME", required=True)
    user_id = _env_str("SEAT_LOCK_ELASTICACHE_USER_ID", "ELASTICACHE_USER_ID", required=True)
    region = os.environ.get("APP_REGION") or os.environ.get("AWS_DEFAULT_REGION")

    now = time.time()
    if _SEATLOCK_REDIS is not None and now < _SEATLOCK_REDIS_REFRESH_AT:
        try:
            _SEATLOCK_REDIS.ping()
            return _SEATLOCK_REDIS
        except Exception as e:
            logger.warning("Seat lock cache health check failed, refreshing client: %s", str(e))
            _SEATLOCK_REDIS = None

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
    refresh_seconds = int(os.environ.get("DB_IAM_TOKEN_REFRESH_SECONDS", "840"))

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
# Key helpers (cluster-safe)
# ----------------------------

def _tag(event_id: str, category_id: str) -> str:
    return f"{{{event_id}:{category_id}}}"


def _queue_allowed_key(event_id: str, category_id: str) -> str:
    tag = _tag(event_id, category_id)
    return f"queue:{tag}:allowed"


def _seat_lock_key(event_id: str, category_id: str, seat_id: str) -> str:
    # Reservation and seat-availability must share this convention.
    tag = _tag(event_id, category_id)
    return f"seatlock:{tag}:{seat_id}"


def _reservation_seats_key(event_id: str, category_id: str, reservation_id: str) -> str:
    tag = _tag(event_id, category_id)
    return f"reservation:{tag}:{reservation_id}:seats"


def _reservation_meta_key(event_id: str, category_id: str, reservation_id: str) -> str:
    tag = _tag(event_id, category_id)
    return f"reservation:{tag}:{reservation_id}:meta"


def _reserve_idempotency_key(event_id: str, category_id: str, user_sub: str, idem_key: str) -> str:
    tag = _tag(event_id, category_id)
    # Keep it in the same tag slot for cluster safety
    return f"reserve:{tag}:{user_sub}:{idem_key}"


def _reservation_lookup_key(reservation_id: str) -> str:
    # Keyed only by reservation_id so the booking service can resolve
    # eventId and categoryId without the client sending them.
    # Written as a separate SETEX after Lua succeeds because this key
    # lands on a different cluster slot from the seat lock keys and
    # cannot be included in the same Lua script (CROSSSLOT constraint).
    return f"reservation:lookup:{reservation_id}"

def _seat_lock_count_key(event_id: str, category_id: str) -> str:
    tag = _tag(event_id, category_id)
    return f"seatlock:{tag}:locked_count"


# ----------------------------
# DB functions
# ----------------------------

def _get_category_pricing(event_id: str, category_id: str) -> Tuple[int, str]:
    """Returns (unit_price, currency) from public.event_categories."""
    global _DB_CONN, _DB_CONN_REFRESH_AT

    sql = """
        SELECT price, currency
        FROM public.event_categories
        WHERE event_id = %s AND id = %s
        LIMIT 1
    """
    for attempt in range(2):
        try:
            conn = _db_conn()
            with conn.cursor() as cur:
                cur.execute(sql, (event_id, category_id))
                row = cur.fetchone()
            if not row:
                raise ValueError("Invalid category for event")
            return int(row[0]), str(row[1])
        except psycopg2.OperationalError:
            if attempt == 0:
                _DB_CONN = None
                _DB_CONN_REFRESH_AT = 0.0
            else:
                raise


def _validate_seats_available(event_id: str, category_id: str, seat_ids: List[str]) -> Dict[str, str]:
    """Validate all requested seats are AVAILABLE in DB and belong to event+category.

    Returns mapping seat_label -> seat_uuid (as string) for inserts into reservation_seats.

    Assumes schema: public.seats(id UUID, event_id UUID, category_id UUID, seat_label TEXT, status TEXT/enum)
    and seat_label is the API seatId.
    """
    global _DB_CONN, _DB_CONN_REFRESH_AT

    if not seat_ids:
        raise ValueError("No seats requested")

    sql = """
        SELECT id, seat_label
        FROM public.seats
        WHERE event_id = %s
          AND category_id = %s
          AND status = 'AVAILABLE'
          AND seat_label = ANY(%s)
    """

    for attempt in range(2):
        try:
            conn = _db_conn()
            with conn.cursor() as cur:
                cur.execute(sql, (event_id, category_id, seat_ids))
                rows = cur.fetchall()
            found = {r[1]: str(r[0]) for r in rows}
            missing = [s for s in seat_ids if s not in found]
            if missing:
                raise ValueError(f"Some seats are not AVAILABLE in DB: {missing}")
            return found
        except psycopg2.OperationalError:
            if attempt == 0:
                _DB_CONN = None
                _DB_CONN_REFRESH_AT = 0.0
            else:
                raise


def _insert_failed_reservation(reservation_id: str, user_sub: str, event_id: str, category_id: str,
                              idempotency_key: Optional[str], failure_reason: str) -> None:
    """Insert reservation row with FAILED status."""
    conn = _db_conn()
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO public.reservations (id, user_id, event_id, category_id, status, idempotency_key, failure_reason, created_at, updated_at)
            VALUES (%s, %s, %s, %s, 'FAILED', %s, %s, now(), now())
            ON CONFLICT DO NOTHING
            """,
            (reservation_id, user_sub, event_id, category_id, idempotency_key, failure_reason),
        )

def _insert_hold_reservation(
    reservation_id: str,
    user_sub: str,
    event_id: str,
    category_id: str,
    idempotency_key: Optional[str] ) -> None:
    """Insert reservation row with HOLD status.

    This row is required before confirmation inserts ticket rows that reference
    tickets.reservation_id -> reservations.id.
    """
    conn = _db_conn()
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO public.reservations (
                id, user_id, event_id, category_id, status, idempotency_key, created_at, updated_at
            )
            VALUES (%s, %s, %s, %s, 'HOLD', %s, now(), now())
            ON CONFLICT (id) DO NOTHING
            """,
            (reservation_id, user_sub, event_id, category_id, idempotency_key),
        )


# KEYS[1..N-3]: seat lock keys
# KEYS[N-2]:    reservation seats key (same hash tag -> same cluster slot)
# KEYS[N-1]:    reservation meta key  (same hash tag -> same cluster slot)
# KEYS[N]:      idempotency key       (same hash tag -> same cluster slot)
#
# ARGV[1]: ttl_seconds
# ARGV[2]: reservation_id (lock value)
# ARGV[3]: seats_json
# ARGV[4]: meta_json
_LOCK_ALL_OR_NOTHING_LUA = r"""
local ttl        = tonumber(ARGV[1])
local res_id     = ARGV[2]
local seats_json = ARGV[3]
local meta_json  = ARGV[4]

local count_key = KEYS[#KEYS - 3]
local seats_key  = KEYS[#KEYS - 2]
local meta_key   = KEYS[#KEYS - 1]
local idem_key   = KEYS[#KEYS]

local n_seats = #KEYS - 4

-- 0) Idempotency: if exists, return existing reservation id
local existing = redis.call('GET', idem_key)
if existing then
  return {2, existing}
end

-- 1) If any seat lock key exists, fail immediately
for i = 1, n_seats do
  if redis.call('EXISTS', KEYS[i]) == 1 then
    return {0, KEYS[i]}
  end
end

-- 2) Lock all seat keys
for i = 1, n_seats do
  redis.call('SET', KEYS[i], res_id, 'EX', ttl, 'NX')
end

-- 3) Increment seat lock count for this event+category (used by queue service for promotion), with identical TTL
redis.call('INCRBY', count_key, n_seats)
redis.call('EXPIRE', count_key, ttl)

-- 4) Write reservation seats mapping + meta with identical TTL
redis.call('SET', seats_key, seats_json, 'EX', ttl)
redis.call('SET', meta_key,  meta_json,  'EX', ttl)

-- 5) Write idempotency key -> reservation id with identical TTL
redis.call('SET', idem_key, res_id, 'EX', ttl)

return {1, ''}
"""


# ----------------------------
# Reservation handler
# ----------------------------

def handle_reserve(event, context):
    user_sub = _get_user_sub_from_rest_api(event)
    if not user_sub:
        return _resp(401, {"error": "UNAUTHORIZED", "message": "Missing Cognito authorizer claims"})

    # Parse request
    try:
        body = _parse_json_body(event)
    except Exception:
        return _resp(400, {"error": "INVALID_JSON"})

    event_id = body.get("eventId")
    category_id = body.get("categoryId")
    seats = body.get("seats") or []
    seat_ids = [s.get("seatId") for s in seats if isinstance(s, dict) and s.get("seatId")]

    # Dedupe to avoid double-locking / double-charging if client sends duplicates
    seat_ids = list(dict.fromkeys(seat_ids))  # preserves order

    # Guardrail: cap seats per reservation
    max_seats = _env_int("MAX_SEATS_PER_RESERVATION", 10)
    if len(seat_ids) > max_seats:
        return _resp(400, {
            "error": "VALIDATION_ERROR",
            "message": f"max {max_seats} seats allowed per reservation"
        })

    if not event_id or not category_id or not seat_ids:
        return _resp(400, {"error": "VALIDATION_ERROR", "message": "eventId, categoryId and seats[].seatId are required"})

    # Booking token header
    h = _headers_lc(event)
    booking_token = h.get("x-booking-token") or h.get("authorization")
    # If Authorization: Bearer <token> is used, extract token
    if booking_token and booking_token.lower().startswith("bearer "):
        booking_token = booking_token.split(" ", 1)[1].strip()

    if not booking_token:
        return _resp(400, {"error": "MISSING_BOOKING_TOKEN", "message": "Provide x-booking-token header (recommended)"})

    # Verify booking token (KMS verify)
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

    if bt.get("scope") != "booking:queue":
        return _resp(401, {"error": "INVALID_BOOKING_TOKEN", "message": "invalid token scope"})

    # Re-check session is ALLOWED in queue cache
    try:
        q = _queue_cache()
        allowed_key = _queue_allowed_key(event_id, category_id)
        if not q.sismember(allowed_key, session_id):
            return _resp(403, {"error": "NOT_ALLOWED", "message": "Session is not allowed (queue admission missing/expired)"})
    except Exception as e:
        logger.exception("Queue cache check failed")
        return _resp(500, {"error": "QUEUE_CACHE_FAILED", "message": str(e)})

    # Determine TTL for locks/reservation
    seat_lock_ttl = _env_int("SEAT_LOCK_TTL_SECONDS", 600)
    expires_at_epoch = int(time.time()) + seat_lock_ttl
    expires_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(expires_at_epoch))

    # Create deterministic reservation_id for this request (always)
    reservation_id = str(uuid.uuid4())

    # Idempotency key is required to make reserveTicket retry-safe
    idem_key_header = h.get("idempotency-key")
    if not idem_key_header:
        return _resp(400, {
            "error": "MISSING_IDEMPOTENCY_KEY",
            "message": "Idempotency-Key header is required"
        })


    # 1) Validate seats are AVAILABLE in DB
    try:
        _validate_seats_available(event_id, category_id, seat_ids)
    except Exception as e:
        try:
            _insert_failed_reservation(reservation_id, user_sub, event_id, category_id, idem_key_header, str(e))
        except Exception:
            logger.exception("Failed to write FAILED reservation record")
        return _resp(409, {
            "reservationId": reservation_id,
            "status": "FAILED",
            "eventId": event_id,
            "categoryId": category_id,
            "expiresAt": None,
            "reason": "SEAT_NOT_AVAILABLE_DB",
            "message": str(e),
            "seats": {"requested": seat_ids, "locked": []}
        })

    # 1b) Compute pricing
    try:
        unit_price, currency = _get_category_pricing(event_id, category_id)
    except Exception as e:
        unit_price, currency = 0, ""
        logger.exception("Pricing lookup failed")
        return _resp(500, {
            "error": "PRICING_LOOKUP_FAILED",
            "message": str(e)
            }
            )
    total_amount = unit_price * len(seat_ids)

    # 2) Atomic lock in cache (all-or-none) + write reservation seats mapping with identical TTL
    try:
        sl = _seatlock_cache()
    except Exception as e:
        logger.exception("Seat-lock cache unavailable")
        return _resp(500, {"error": "SEAT_LOCK_CACHE_UNAVAILABLE", "message": str(e)})

    lock_keys = [_seat_lock_key(event_id, category_id, sid) for sid in seat_ids]

    # Locked count key for this event+category (used by queue service for promotion), with identical TTL
    count_key = _seat_lock_count_key(event_id, category_id)
    

    # Existing seats list key
    reservation_seats_key = _reservation_seats_key(event_id, category_id, reservation_id)

    # Reservation meta key (pricing, expiry)
    reservation_meta_key = _reservation_meta_key(event_id, category_id, reservation_id)

    # Idempotency mapping key (stable reservationId for retries)
    idem_key = _reserve_idempotency_key(event_id, category_id, user_sub, idem_key_header)

    # KEYS includes: seatlock keys + seats key + meta key + idempotency key
    all_keys = lock_keys + [count_key, reservation_seats_key, reservation_meta_key, idem_key]

    # Values
    lock_value = reservation_id
    seats_json = json.dumps(seat_ids)

    meta_json = json.dumps({
        "reservationId": reservation_id,
        "eventId": event_id,
        "categoryId": category_id,
        "currency": currency,
        "unitPrice": unit_price,
        "quantity": len(seat_ids),
        "totalAmount": total_amount,
        "expiresAt": expires_at
    })

    try:
        rc, info = sl.eval(
            _LOCK_ALL_OR_NOTHING_LUA,
            len(all_keys),
            *all_keys,
            seat_lock_ttl,
            lock_value,
            seats_json,
            meta_json
        )
        rc = int(rc)

        if rc == 2:
            #Idempotent replay: Lua returns existing reservationId in `info`
            existing_res_id = str(info)
            existing_seats_key = _reservation_seats_key(event_id, category_id, existing_res_id)
            existing_meta_key  = _reservation_meta_key(event_id, category_id, existing_res_id)

            existing_meta_raw = sl.get(existing_meta_key)
            existing_seats_raw = sl.get(existing_seats_key)

            if not existing_meta_raw or not existing_seats_raw:
                # Idempotency key exists but reservation keys have expired.
                # Delete the stale idempotency key and tell the client to retry.
                sl.delete(idem_key)
                return _resp(409, {
                    "error": "RESERVATION_EXPIRED",
                    "message": "Previous reservation expired. Please reserve again."
                })

            meta = json.loads(existing_meta_raw)
            locked_seats = json.loads(existing_seats_raw)

            # Ensure the HOLD reservation row exists in DB for downstream FK integrity.
            try:
                _insert_hold_reservation(
                    reservation_id=existing_res_id,
                    user_sub=user_sub,
                    event_id=event_id,
                    category_id=category_id,
                    idempotency_key=idem_key_header,
                )
            except Exception as e:
                logger.exception("Failed to persist HOLD reservation on idempotent replay")
                return _resp(500, {
                    "error": "RESERVATION_PERSIST_FAILED",
                    "message": str(e)
                })

            return _resp(200, {
                "reservationId": existing_res_id,
                "status": "SUCCESS",
                "expiresAt": meta.get("expiresAt"),
                "eventId": meta.get("eventId"),
                "categoryId": meta.get("categoryId"),
                "pricing": {
                    "currency": meta.get("currency"),
                    "unitPrice": meta.get("unitPrice"),
                    "quantity": meta.get("quantity"),
                    "totalAmount": meta.get("totalAmount")
                },
                "seats": {
                    "requested": seat_ids,
                    "locked": locked_seats
                },
                "nextActions": {
                    "canProceedToPayment": True,
                    "canCancel": True
                }
            })



        if rc != 1:
            failure = f"Seat already locked: {info}"
            try:
                _insert_failed_reservation(reservation_id, user_sub, event_id, category_id, idem_key_header, failure)
            except Exception:
                logger.exception("Failed to write FAILED reservation record")
            return _resp(409, {
                "reservationId": reservation_id,
                "status": "FAILED",
                "eventId": event_id,
                "categoryId": category_id,
                "expiresAt": None,
                "reason": "SEAT_ALREADY_LOCKED_CACHE",
                "message": failure,
                "seats": {"requested": seat_ids, "locked": []}
            })

    except Exception as e:
        logger.exception("Seat lock Lua execution failed")
        return _resp(500, {"error": "SEAT_LOCK_FAILED", "message": str(e)})

    # Write lookup key so booking service can resolve eventId/categoryId from reservationId alone.
    # This is REQUIRED because confirmation depends on it.
    
    try:
            sl.setex(
                _reservation_lookup_key(reservation_id),
                seat_lock_ttl,
                json.dumps({"eventId": event_id, "categoryId": category_id}),
                )
    except Exception as e:
            logger.exception("Failed to write reservation lookup key (fatal)")

            # Cleanup everything written in cache for this reservation
            try:
                n = len(lock_keys)
                if n > 0:
                    new_val = sl.decrby(count_key, n)
                    if int(new_val) < 0:
                        logger.warning(f"Seat lock count for {event_id}/{category_id} went negative, resetting to 0")
                        sl.set(count_key, 0)

                sl.delete(
                    *lock_keys,
                    reservation_seats_key,
                    reservation_meta_key,
                    idem_key
                )
            except Exception:
                logger.exception("Failed to clean up reservation cache keys after lookup-key failure")

            return _resp(500, {
                "error": "RESERVATION_LOOKUP_WRITE_FAILED",
                "message": str(e)
            })

        # Persist HOLD reservation row in DB so confirmation can safely reference it from tickets.
    try:
        _insert_hold_reservation(
            reservation_id=reservation_id,
            user_sub=user_sub,
            event_id=event_id,
            category_id=category_id,
            idempotency_key=idem_key_header,
        )
    except Exception as e:
        logger.exception("Failed to persist HOLD reservation")

        # Cleanup cache because reservation DB row is required for later confirmation.
        try:
            n = len(lock_keys)
            if n > 0:
                new_val = sl.decrby(count_key, n)
                if int(new_val) < 0:
                    logger.warning(f"Seat lock count for {event_id}/{category_id} went negative, resetting to 0")
                    sl.set(count_key, 0)

            sl.delete(
                *lock_keys,
                reservation_seats_key,
                reservation_meta_key,
                idem_key,
                _reservation_lookup_key(reservation_id),
            )
        except Exception:
            logger.exception("Failed to cleanup reservation cache after HOLD DB insert failure")

        return _resp(500, {
            "error": "RESERVATION_PERSIST_FAILED",
            "message": str(e)
        })

    return _resp(200, {
        "reservationId": reservation_id,
        "status": "SUCCESS",
        "expiresAt": expires_at,
        "eventId": event_id,
        "categoryId": category_id,
        "pricing": {
            "currency": currency,
            "unitPrice": unit_price,
            "quantity": len(seat_ids),
            "totalAmount": total_amount
        },
        "seats": {
            "requested": seat_ids,
            "locked": seat_ids
        },
        "nextActions": {
            "canProceedToPayment": True,
            "canCancel": True
        }
    })



# ----------------------------
# Main router
# ----------------------------

def handler(event, context):
    path = (event.get("resource") or event.get("path") or "").lower()
    method = (event.get("httpMethod") or "").upper()

    if method == "POST" and path.endswith("/v1/reserveticket"):
        return handle_reserve(event, context)

    return _resp(404, {"error": "NOT_FOUND", "message": f"Unsupported route {method} {path}"})
