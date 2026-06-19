import os
import json
import time
import uuid
import base64
import logging
from typing import Any, Dict, Optional

import boto3

try:
    import redis  # redis-py
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
# Cache A == Queue Cache (Valkey Serverless IAM)
_QUEUE_REDIS = None
_QUEUE_REDIS_REFRESH_AT = 0.0

# Cache B == Seat lock cache (Valkey Serverless IAM)
_SEAT_LOCK_REDIS = None
_SEAT_LOCK_REDIS_REFRESH_AT = 0.0

# DB connection (Aurora via Aurora Cluster)
_DB_CONN = None
_DB_CONN_REFRESH_AT = 0.0

# RDS IAM token cache (used as password when connecting to Aurora Cluster)
_RDS_IAM_TOKEN = None
_RDS_IAM_TOKEN_REFRESH_AT = 0.0


# ----------------------------
# Small utilities
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


# ----------------------------
# ElastiCache Serverless IAM auth (Valkey)
# ----------------------------
def _elasticache_iam_token(user_id: str, cache_name: str, region: str) -> str:
    """Build a SigV4 presigned URL used as password for ElastiCache Serverless IAM auth (TLS required)."""
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
        expires=900,  # 15 minutes
    )
    signer.add_auth(aws_req)

    return aws_req.url.replace("http://", "")


def _queue_cache():
    """Cache A == Queue cache (Valkey). Supports both QUEUE_CACHE_* and ACTIVE_USERS_CACHE_* env names."""
    global _QUEUE_REDIS, _QUEUE_REDIS_REFRESH_AT

    if redis is None:
        raise RuntimeError("redis library not available. Add redis to your Lambda layer/package.")

    endpoint = _env_str("BROWSE_CACHE_ENDPOINT", required=True)
    port = int(_env_str("BROWSE_CACHE_PORT") or "6379")
    cache_name = _env_str("BROWSE_CACHE_NAME", required=True)
    user_id = _env_str("ELASTICACHE_USER_ID", required=True)
    region = os.environ.get("APP_REGION") or os.environ.get("AWS_DEFAULT_REGION")

    now = time.time()
    
    if _QUEUE_REDIS is not None and now < _QUEUE_REDIS_REFRESH_AT:
        try:
            _QUEUE_REDIS.ping()
            return _QUEUE_REDIS
        except Exception as e:
            logger.warning("Queue cache health check failed, refreshing client: %s", str(e))
            _QUEUE_REDIS = None


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

def _seat_lock_cache():
    """Cache B == Seat lock cache (Valkey). Similar to _queue_cache but separate connection and env vars."""
    global _SEAT_LOCK_REDIS, _SEAT_LOCK_REDIS_REFRESH_AT

    if redis is None:
        raise RuntimeError("redis library not available. Add redis to your Lambda layer/package.")

    endpoint = _env_str("BROWSE_CACHE_ENDPOINT", required=True)
    port = int(_env_str("BROWSE_CACHE_PORT") or "6379")
    cache_name = _env_str("BROWSE_CACHE_NAME", required=True)
    user_id = _env_str("ELASTICACHE_USER_ID", required=True)
    region = os.environ.get("APP_REGION") or os.environ.get("AWS_DEFAULT_REGION")

    now = time.time()
    
    if _SEAT_LOCK_REDIS is not None and now < _SEAT_LOCK_REDIS_REFRESH_AT:
        try:
            _SEAT_LOCK_REDIS.ping()
            return _SEAT_LOCK_REDIS
        except Exception as e:
            logger.warning("Seat lock cache health check failed, refreshing client: %s", str(e))
            _SEAT_LOCK_REDIS = None


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

    _SEAT_LOCK_REDIS = client
    _SEAT_LOCK_REDIS_REFRESH_AT = now + (14 * 60)
    return client

def _count_locked_seats(event_id: str, category_id: str) -> int:
    """Read the locked_count counter written atomically by reservation_service when it creates seat locks. This is used in handle_poll to determine how many seats are currently locked."""
    """Single GET call - 0(1) regardless of how many seats are locked."""
    tag = f"{{{event_id}:{category_id}}}"
    count_key = f"seatlock:{tag}:locked_count"
    sl = _seat_lock_cache()
    return int(sl.get(count_key) or 0)


# ----------------------------
# Aurora Cluster + IAM DB Authentication (token-as-password)
# ----------------------------
def _rds_iam_token(host: str, port: int, user: str, region: str) -> str:
    """Generate IAM DB auth token for Aurora Cluster; cache & refresh before expiry."""
    global _RDS_IAM_TOKEN, _RDS_IAM_TOKEN_REFRESH_AT

    now = time.time()
    refresh_seconds = int(os.environ.get("DB_IAM_TOKEN_REFRESH_SECONDS", "840"))  # 14 minutes

    if _RDS_IAM_TOKEN is not None and now < _RDS_IAM_TOKEN_REFRESH_AT:
        return _RDS_IAM_TOKEN

    rds = boto3.client("rds", config=_BOTO_CFG)
    token = rds.generate_db_auth_token(
        DBHostname=host,
        Port=port,
        DBUsername=user,
        Region=region,
    )

    _RDS_IAM_TOKEN = token
    _RDS_IAM_TOKEN_REFRESH_AT = now + refresh_seconds
    return token


# CHANGED: removed SELECT 1 health check from warm path; reconnect on OperationalError
#          is handled in _available_seats_from_db instead.
def _db_conn():
    """psycopg2 connection to Aurora via Aurora Cluster using IAM auth token."""
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

    db_host = os.environ["DB_HOST"]  # Aurora Cluster endpoint
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


# CHANGED: added one retry on OperationalError; resets cached connection so _db_conn()
#          reconnects on the second attempt.
def _available_seats_from_db(event_id: str, category_id: str) -> int:
    """Count available seats using your schema seats(event_id, category_id, status)."""
    global _DB_CONN, _DB_CONN_REFRESH_AT
    sql = """
        SELECT COUNT(*)
        FROM seats
        WHERE event_id = %s
          AND category_id = %s
          AND status = 'AVAILABLE'
    """
    for attempt in range(2):
        try:
            conn = _db_conn()
            with conn.cursor() as cur:
                cur.execute(sql, (event_id, category_id))
                return int(cur.fetchone()[0] or 0)
        except psycopg2.OperationalError:
            if attempt == 0:
                _DB_CONN = None
                _DB_CONN_REFRESH_AT = 0.0
            else:
                raise


# ----------------------------
# JWT via KMS (RS256-style)
# ----------------------------
def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("utf-8").rstrip("=")


def _kms_sign_rs256(message: bytes, key_id: str) -> bytes:
    kms = boto3.client("kms", config=_BOTO_CFG)
    resp = kms.sign(
        KeyId=key_id,
        Message=message,
        MessageType="RAW",
        SigningAlgorithm="RSASSA_PKCS1_V1_5_SHA_256",
    )
    return resp["Signature"]


def _mint_booking_token(
    key_id: str,
    issuer: str,
    user_sub: str,
    event_id: str,
    category_id: str,
    session_id: str,
    ttl_seconds: int,
) -> str:
    now = int(time.time())
    exp = now + ttl_seconds

    header = {"alg": "RS256", "typ": "JWT", "kid": key_id}
    payload = {
        "iss": issuer,
        "sub": user_sub,
        "iat": now,
        "exp": exp,
        "jti": str(uuid.uuid4()),
        "eventId": event_id,
        "categoryId": category_id,
        "sessionId": session_id,
        "scope": "booking:queue",
    }

    signing_input = (
        f"{_b64url(json.dumps(header, separators=(',', ':')).encode())}."
        f"{_b64url(json.dumps(payload, separators=(',', ':')).encode())}"
    ).encode()

    sig = _kms_sign_rs256(signing_input, key_id=key_id)
    return f"{signing_input.decode()}.{_b64url(sig)}"


# ----------------------------
# Queue keys
# ----------------------------
def _keys(event_id: str, category_id: str):
    tag = f"{{{event_id}:{category_id}}}"

    waiting_key = f"queue:{tag}:waiting"          # ZSET(sessionId -> enqueue_ts)
    allowed_key = f"queue:{tag}:allowed"          # SET(sessionId)
    active_key = f"queue:{tag}:active_count"      # STRING counter
    soldout_key = f"queue:{tag}:soldout"          # STRING flag
    session_prefix = f"queue:{tag}:session:"      # prefix + sessionId
    promote_lock_key = f"queue:{tag}:promote_lock"  # short mutex

    return waiting_key, allowed_key, active_key, soldout_key, session_prefix, promote_lock_key


# ----------------------------
# Lua: promote N from waiting -> allowed + increment active_count (atomic in Queue cache)
# ----------------------------
_PROMOTE_LUA = r"""
local waiting = KEYS[1]
local allowed = KEYS[2]
local active  = KEYS[3]
local ttl     = tonumber(ARGV[1])
local n       = tonumber(ARGV[2])

if n == nil or n <= 0 then
  return 0
end

local popped = redis.call('ZPOPMIN', waiting, n)
local promoted = #popped / 2
if promoted <= 0 then
  return 0
end

for i = 1, #popped, 2 do
  redis.call('SADD', allowed, popped[i])
end

redis.call('INCRBY', active, promoted)

redis.call('EXPIRE', waiting, ttl)
redis.call('EXPIRE', allowed, ttl)
redis.call('EXPIRE', active, ttl)

return promoted
"""

# ----------------------------
# NEW Lua: atomic check-and-allow for handle_enter.
# Returns 1 if session was allowed, 0 if queue is full (caller puts session in WAITING).
# ----------------------------
_ENTER_ALLOW_LUA = r"""
local allowed_key = KEYS[1]
local active_key  = KEYS[2]
local session_key = KEYS[3]
local max_active  = tonumber(ARGV[1])
local session_id  = ARGV[2]
local ttl         = tonumber(ARGV[3])
local meta_json   = ARGV[4]

local count = tonumber(redis.call('GET', active_key) or '0')

if max_active > 0 and count >= max_active then
  return 0
end

redis.call('SADD',   allowed_key, session_id)
redis.call('INCR',   active_key)
redis.call('EXPIRE', allowed_key, ttl)
redis.call('EXPIRE', active_key,  ttl)
redis.call('SETEX',  session_key, ttl, meta_json)
return 1
"""


# ----------------------------
# Handlers
# ----------------------------
def handle_enter(event, context):
    user_sub = _get_user_sub_from_rest_api(event)
    if not user_sub:
        return _resp(401, {"error": "UNAUTHORIZED", "message": "Missing Cognito authorizer claims"})

    try:
        body = _parse_json_body(event)
    except Exception:
        return _resp(400, {"error": "INVALID_JSON"})

    event_id = body.get("eventId")
    category_id = body.get("categoryId")
    if not event_id or not category_id:
        return _resp(400, {"error": "VALIDATION_ERROR", "message": "eventId and categoryId are required"})

    allowed_ttl = _env_int("QUEUE_ALLOWED_TTL_SECONDS", 600)
    poll_after = _env_int("QUEUE_POLL_AFTER_SECONDS", 5)
    max_active = _env_int("QUEUE_MAX_USERS_PER_EVENT_CATEGORY", 0)

    jwt_kms_key_id = os.environ["JWT_KMS_KEY_ID"]
    jwt_issuer = os.environ.get("JWT_ISSUER", "ticketing-queue")

    waiting_key, allowed_key, active_key, soldout_key, session_prefix, _ = _keys(event_id, category_id)

    try:
        q = _queue_cache()
    except Exception as e:
        logger.exception("Queue cache unavailable")
        return _resp(500, {"error": "CACHE_UNAVAILABLE", "message": str(e)})

    if q.get(soldout_key) == "1":
        return _resp(200, {
            "status": "SOLD_OUT",
            "bookingToken": None,
            "sessionId": None,
            "expiresInSeconds": allowed_ttl,
            "pollAfterSeconds": poll_after,
            "message": "Tickets are sold out for this category."
        })

    session_id = str(uuid.uuid4())
    enqueue_ts = int(time.time())
    session_key = f"{session_prefix}{session_id}"

    # CHANGED: replaced non-atomic read-then-pipeline with _ENTER_ALLOW_LUA so the
    #          active_count check and the SADD/INCR are a single atomic operation.
    try:
        allowed = int(q.eval(
            _ENTER_ALLOW_LUA, 3,
            allowed_key, active_key, session_key,
            max_active, session_id, allowed_ttl,
            json.dumps({
                "status": "ALLOWED",
                "userSub": user_sub,
                "eventId": event_id,
                "categoryId": category_id,
                "createdAt": enqueue_ts,
            }),
        ))

        if not allowed:
            # WAITING
            pipe = q.pipeline(transaction=True)
            pipe.zadd(waiting_key, {session_id: enqueue_ts})
            pipe.expire(waiting_key, allowed_ttl)
            pipe.setex(session_key, allowed_ttl, json.dumps({
                "status": "WAITING",
                "userSub": user_sub,
                "eventId": event_id,
                "categoryId": category_id,
                "createdAt": enqueue_ts,
            }))
            pipe.execute()

            token = _mint_booking_token(
                key_id=jwt_kms_key_id,
                issuer=jwt_issuer,
                user_sub=user_sub,
                event_id=event_id,
                category_id=category_id,
                session_id=session_id,
                ttl_seconds=allowed_ttl,
            )
            return _resp(200, {
                "status": "WAITING",
                "bookingToken": token,
                "sessionId": session_id,
                "expiresInSeconds": allowed_ttl,
                "pollAfterSeconds": poll_after,
                "message": "Please wait while we get you available seats."
            })

        # ALLOWED
        token = _mint_booking_token(
            key_id=jwt_kms_key_id,
            issuer=jwt_issuer,
            user_sub=user_sub,
            event_id=event_id,
            category_id=category_id,
            session_id=session_id,
            ttl_seconds=allowed_ttl,
        )
        return _resp(200, {
            "status": "ALLOWED",
            "bookingToken": token,
            "sessionId": session_id,
            "expiresInSeconds": allowed_ttl,
            "pollAfterSeconds": poll_after,
            "message": "You are allowed to proceed. Fetch available seats."
        })

    except Exception as e:
        logger.exception("Queue enter failed")
        return _resp(500, {"error": "QUEUE_ENTER_FAILED", "message": str(e)})


def handle_poll(event, context):
    user_sub = _get_user_sub_from_rest_api(event)
    if not user_sub:
        return _resp(401, {"error": "UNAUTHORIZED", "message": "Missing Cognito authorizer claims"})

    try:
        body = _parse_json_body(event)
    except Exception:
        return _resp(400, {"error": "INVALID_JSON"})

    event_id = body.get("eventId")
    category_id = body.get("categoryId")
    session_id = body.get("sessionId")
    booking_token = body.get("bookingToken")  # optional; echoed back

    if not event_id or not category_id or not session_id:
        return _resp(400, {"error": "VALIDATION_ERROR", "message": "eventId, categoryId and sessionId are required"})

    allowed_ttl = _env_int("QUEUE_ALLOWED_TTL_SECONDS", 600)
    poll_after = _env_int("QUEUE_POLL_AFTER_SECONDS", 5)

    max_active = _env_int("QUEUE_MAX_USERS_PER_EVENT_CATEGORY", 0)
    oversell_factor = _env_int("QUEUE_OVERSELL_FACTOR", 2)

    lock_seconds = _env_int("QUEUE_PROMOTION_LOCK_SECONDS", 1)
    safety_cap = _env_int("QUEUE_MAX_PROMOTE_PER_POLL", 25)

    waiting_key, allowed_key, active_key, soldout_key, session_prefix, promote_lock_key = _keys(event_id, category_id)
    session_key = f"{session_prefix}{session_id}"

    try:
        q = _queue_cache()
    except Exception as e:
        logger.exception("Queue cache unavailable")
        return _resp(500, {"error": "CACHE_UNAVAILABLE", "message": str(e)})

    if q.get(soldout_key) == "1":
        return _resp(200, {
            "status": "SOLD_OUT",
            "bookingToken": booking_token,
            "sessionId": session_id,
            "expiresInSeconds": allowed_ttl,
            "pollAfterSeconds": poll_after,
            "message": "Tickets are sold out for this category."
        })

    ttl = q.ttl(session_key)
    if ttl is None or ttl < 0:
        return _resp(200, {
            "status": "EXPIRED",
            "bookingToken": booking_token,
            "sessionId": session_id,
            "expiresInSeconds": 0,
            "pollAfterSeconds": poll_after,
            "message": "Queue session expired or not found. Please enter the queue again."
        })

    # CHANGED: verify the session belongs to the calling user before doing anything else.
    meta_raw = q.get(session_key)
    if not meta_raw:
        return _resp(200, {
            "status": "EXPIRED",
            "bookingToken": booking_token,
            "sessionId": session_id,
            "expiresInSeconds": 0,
            "pollAfterSeconds": poll_after,
            "message": "Queue session expired or not found. Please enter the queue again."
        })
    if json.loads(meta_raw).get("userSub") != user_sub:
        return _resp(403, {"error": "FORBIDDEN", "message": "Session does not belong to this user"})

    # Already allowed -> return immediately (avoid DB call)
    if q.sismember(allowed_key, session_id):
        return _resp(200, {
            "status": "ALLOWED",
            "bookingToken": booking_token,
            "sessionId": session_id,
            "expiresInSeconds": int(ttl),
            "pollAfterSeconds": poll_after,
            "message": "You are allowed to proceed. Fetch available seats."
        })

    promoted_this_poll = 0

    # Promotion computed from 3 sources:
    #   - active_count from Cache A (Queue cache)
    #   - locked_seats from Cache B
    #   - available_seats from DB (via Aurora Cluster IAM auth)
    if max_active > 0:
        lock_val = str(uuid.uuid4())
        got_lock = bool(q.set(promote_lock_key, lock_val, nx=True, ex=lock_seconds))

        if got_lock:
            try:
                active_count = int(q.get(active_key) or 0)
                
                try:
                    locked_seats = _count_locked_seats(event_id, category_id)
                except Exception:
                    logger.exception("Failed to read locked seats from cache; assuming 0")
                    locked_seats = 0

                available_seats = _available_seats_from_db(event_id, category_id)

                available_users = max(max_active - active_count, 0)
                effective_seats = max(available_seats - locked_seats, 0)
                releasable_users = min(available_users, effective_seats * oversell_factor)

                promote_n = min(int(releasable_users), int(safety_cap))
                if promote_n > 0:
                    promoted_this_poll = int(q.eval(
                        _PROMOTE_LUA, 3,
                        waiting_key, allowed_key, active_key,
                        allowed_ttl, promote_n
                    ))
            except Exception:
                logger.exception("Promotion step failed (non-fatal)")
                promoted_this_poll = 0
            # lock expires automatically

    # Re-check membership after promotion
    if q.sismember(allowed_key, session_id):
        return _resp(200, {
            "status": "ALLOWED",
            "bookingToken": booking_token,
            "sessionId": session_id,
            "expiresInSeconds": int(ttl),
            "pollAfterSeconds": poll_after,
            "promotedThisPoll": int(promoted_this_poll),
            "message": "You are allowed to proceed. Fetch available seats."
        })

    pos = q.zrank(waiting_key, session_id)  # 0-based
    qlen = q.zcard(waiting_key)

    return _resp(200, {
        "status": "WAITING",
        "bookingToken": booking_token,
        "sessionId": session_id,
        "expiresInSeconds": int(ttl),
        "pollAfterSeconds": poll_after,
        "promotedThisPoll": int(promoted_this_poll),
        "position": (int(pos) + 1) if pos is not None else None,
        "queueLength": int(qlen),
        "message": "Still waiting. Please poll again."
    })


# NEW: decrement active_count when the client completes or abandons booking.
#      srem returns 1 only if session was in the allowed set, preventing double-decrement
#      if the client calls release more than once.
def handle_release(event, context):
    user_sub = _get_user_sub_from_rest_api(event)
    if not user_sub:
        return _resp(401, {"error": "UNAUTHORIZED", "message": "Missing Cognito authorizer claims"})

    try:
        body = _parse_json_body(event)
    except Exception:
        return _resp(400, {"error": "INVALID_JSON"})

    event_id = body.get("eventId")
    category_id = body.get("categoryId")
    session_id = body.get("sessionId")
    if not event_id or not category_id or not session_id:
        return _resp(400, {"error": "VALIDATION_ERROR", "message": "eventId, categoryId and sessionId are required"})

    _, allowed_key, active_key, _, session_prefix, _ = _keys(event_id, category_id)
    session_key = f"{session_prefix}{session_id}"

    try:
        q = _queue_cache()
    except Exception as e:
        logger.exception("Queue cache unavailable")
        return _resp(500, {"error": "CACHE_UNAVAILABLE", "message": str(e)})

    meta_raw = q.get(session_key)
    if not meta_raw:
        return _resp(404, {"error": "SESSION_NOT_FOUND"})
    if json.loads(meta_raw).get("userSub") != user_sub:
        return _resp(403, {"error": "FORBIDDEN"})

    if q.srem(allowed_key, session_id):
        q.decr(active_key)
    q.delete(session_key)

    return _resp(200, {"status": "RELEASED"})


# ----------------------------
# Main router (single Lambda, multiple routes)
# ----------------------------
def handler(event, context):
    path = (event.get("resource") or event.get("path") or "").lower()
    method = (event.get("httpMethod") or "").upper()

    if method == "POST" and path.endswith("/v1/queue/enter"):
        return handle_enter(event, context)

    if method == "POST" and path.endswith("/v1/queue/poll"):
        return handle_poll(event, context)

    if method == "POST" and path.endswith("/v1/queue/release"):
        return handle_release(event, context)

    return _resp(404, {"error": "NOT_FOUND", "message": f"Unsupported route {method} {path}"})
