import os
import json
import time
import base64
import logging
from typing import Any, Dict, Optional, List, Tuple

import boto3
import psycopg2
import psycopg2.extras

try:
    import redis
except Exception:
    redis = None

from botocore.session import Session
from botocore.auth import SigV4QueryAuth
from botocore.awsrequest import AWSRequest

logger = logging.getLogger()
logger.setLevel(logging.INFO)

_DB = None
_DB_REFRESH_AT = 0.0

_VALKEY_ACTIVE = None
_VALKEY_ACTIVE_REFRESH_AT = 0.0

_VALKEY_SEATLOCK = None
_VALKEY_SEATLOCK_REFRESH_AT = 0.0

# ----------------------------
# Helpers
# ----------------------------
def resp(status: int, body: Any) -> Dict[str, Any]:
    return {
        "statusCode": status,
        "headers": {
            "content-type": "application/json",
            "access-control-allow-origin": "*",
        },
        "body": json.dumps(body, default=str),
    }

def get_sub_from_authorizer(event: Dict[str, Any]) -> Optional[str]:
    # REST API + Cognito authorizer passes claims here
    rc = event.get("requestContext") or {}
    auth = rc.get("authorizer") or {}
    claims = auth.get("claims") or {}
    return claims.get("sub")

def b64url_decode(s: str) -> bytes:
    pad = '=' * (-len(s) % 4)
    return base64.urlsafe_b64decode(s + pad)

def b64url_encode(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).decode("utf-8").rstrip("=")

# ----------------------------
# DB IAM auth via RDS Proxy
# ----------------------------
def db_token() -> str:
    region = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION")
    rds = boto3.client("rds", region_name=region)
    return rds.generate_db_auth_token(
        DBHostname=os.environ["DB_HOST"],
        Port=int(os.environ.get("DB_PORT", "5432")),
        DBUsername=os.environ["DB_USER"],
        Region=region
    )

def db_conn():
    global _DB, _DB_REFRESH_AT
    now = time.time()
    if _DB and now < _DB_REFRESH_AT:
        return _DB

    conn = psycopg2.connect(
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", "5432")),
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=db_token(),
        sslmode="require",
        connect_timeout=5,
        cursor_factory=psycopg2.extras.RealDictCursor
    )
    conn.autocommit = True
    _DB = conn
    _DB_REFRESH_AT = now + (14 * 60)
    return conn

# ----------------------------
# Valkey IAM auth (Serverless)
# ----------------------------
def elasticache_iam_token(user_id: str, cache_name: str, region: str) -> str:
    # Serverless cache IAM auth uses SigV4 presigned URL token (as password) and requires TLS. [3](https://stackoverflow.com/questions/79384089/how-to-delete-keys-matching-pattern-in-aws-elasticache-valkey)
    cache_name = cache_name.lower()
    url = f"http://{cache_name}/"
    params = {"Action": "connect", "User": user_id, "ResourceType": "ServerlessCache"}

    aws_req = AWSRequest(method="GET", url=url, params=params)
    sess = Session()
    creds = sess.get_credentials().get_frozen_credentials()

    signer = SigV4QueryAuth(credentials=creds, service_name="elasticache", region_name=region, expires=900)
    signer.add_auth(aws_req)

    return aws_req.url.replace("http://", "")

def valkey_client(endpoint_env: str, port_env: str, name_env: str, cache_obj_ref: str):
    global _VALKEY_ACTIVE, _VALKEY_ACTIVE_REFRESH_AT, _VALKEY_SEATLOCK, _VALKEY_SEATLOCK_REFRESH_AT

    if redis is None:
        raise RuntimeError("redis library missing from layer/package")

    region = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION")
    endpoint = os.environ[endpoint_env]
    port = int(os.environ.get(port_env, "6379"))
    cache_name = os.environ[name_env]
    user_id = os.environ["ELASTICACHE_USER_ID"]

    now = time.time()

    if cache_obj_ref == "active":
        if _VALKEY_ACTIVE and now < _VALKEY_ACTIVE_REFRESH_AT:
            return _VALKEY_ACTIVE
    else:
        if _VALKEY_SEATLOCK and now < _VALKEY_SEATLOCK_REFRESH_AT:
            return _VALKEY_SEATLOCK

    token = elasticache_iam_token(user_id=user_id, cache_name=cache_name, region=region)

    client = redis.Redis(
        host=endpoint,
        port=port,
        username=user_id,       # IAM-enabled user id must equal username. [3](https://stackoverflow.com/questions/79384089/how-to-delete-keys-matching-pattern-in-aws-elasticache-valkey)
        password=token,
        ssl=True,               # TLS required for IAM auth. [3](https://stackoverflow.com/questions/79384089/how-to-delete-keys-matching-pattern-in-aws-elasticache-valkey)
        ssl_cert_reqs=None,
        decode_responses=True,
        socket_connect_timeout=2,
        socket_timeout=2,
    )
    client.ping()

    if cache_obj_ref == "active":
        _VALKEY_ACTIVE = client
        _VALKEY_ACTIVE_REFRESH_AT = now + (14 * 60)
    else:
        _VALKEY_SEATLOCK = client
        _VALKEY_SEATLOCK_REFRESH_AT = now + (14 * 60)

    return client

# ----------------------------
# Booking token verification using KMS Verify (no cryptography dependency)
# ----------------------------
def verify_booking_jwt(token: str) -> Dict[str, Any]:
    """
    bookingToken is a JWT. We verify signature using KMS Verify with the same KMS key.
    """
    parts = token.split(".")
    if len(parts) != 3:
        raise ValueError("Invalid bookingToken format")

    header_b64, payload_b64, sig_b64 = parts
    signing_input = f"{header_b64}.{payload_b64}".encode()
    signature = b64url_decode(sig_b64)

    header = json.loads(b64url_decode(header_b64).decode("utf-8"))
    payload = json.loads(b64url_decode(payload_b64).decode("utf-8"))

    # basic claim checks
    issuer = os.environ.get("JWT_ISSUER", "ticketing-queue")
    now = int(time.time())
    if payload.get("iss") != issuer:
        raise ValueError("Invalid issuer")
    if int(payload.get("exp", 0)) < now:
        raise ValueError("Token expired")

    kms = boto3.client("kms")
    kms.verify(
        KeyId=os.environ["JWT_KMS_KEY_ID"],
        Message=signing_input,
        MessageType="RAW",
        Signature=signature,
        SigningAlgorithm="RSASSA_PKCS1_V1_5_SHA_256",
    )
    # if verify fails, boto3 raises an exception
    return payload

# ----------------------------
# Handler
# ----------------------------
def handler(event, context):
    user_sub = get_sub_from_authorizer(event)
    if not user_sub:
        return resp(401, {"error": "UNAUTHORIZED"})

    # REST API pathParameters
    path_params = event.get("pathParameters") or {}
    event_id = path_params.get("eventId")
    qs = event.get("queryStringParameters") or {}
    category_id = qs.get("category_id")

    if not event_id or not category_id:
        return resp(400, {"error": "VALIDATION_ERROR", "message": "eventId and category_id are required"})

    # bookingToken expected in header
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    booking_token = headers.get("x-booking-token")
    if not booking_token:
        return resp(400, {"error": "MISSING_BOOKING_TOKEN", "message": "x-booking-token header required"})

    # verify booking token and bind to request scope
    try:
        bt = verify_booking_jwt(booking_token)
    except Exception as e:
        return resp(401, {"error": "INVALID_BOOKING_TOKEN", "message": str(e)})

    if bt.get("sub") != user_sub:
        return resp(403, {"error": "TOKEN_USER_MISMATCH"})
    if bt.get("eventId") != event_id or bt.get("categoryId") != category_id:
        return resp(403, {"error": "TOKEN_SCOPE_MISMATCH"})

    session_id = bt.get("sessionId")
    if not session_id:
        return resp(401, {"error": "INVALID_BOOKING_TOKEN", "message": "sessionId missing"})

    # compute hash-tag base for cluster-safe keys
    tag = f"{{{event_id}:{category_id}}}"

    # check ALLOWED in active-users cache
    try:
        r_active = valkey_client("ACTIVE_USERS_CACHE_ENDPOINT", "ACTIVE_USERS_CACHE_PORT", "ACTIVE_USERS_CACHE_NAME", "active")
    except Exception as e:
        logger.exception("active-users cache unavailable")
        return resp(500, {"error": "CACHE_UNAVAILABLE", "message": str(e)})

    allowed_key = f"queue:{tag}:allowed"
    if not r_active.sismember(allowed_key, session_id):
        return resp(200, {
            "eventId": event_id,
            "categoryId": category_id,
            "asOf": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "seats": [],
            "status": "WAITING",
            "message": "You are not admitted yet. Please keep polling."
        })

    # fetch seats from DB
    try:
        conn = db_conn()
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT seat_number, seat_row, seat_no, status
                FROM public.seats
                WHERE event_id = %s AND category_id = %s
                ORDER BY seat_number
                LIMIT %s;
                """,
                (event_id, category_id, int(os.environ.get("SEATS_PAGE_SIZE", "200"))),
            )
            rows = cur.fetchall()
    except Exception as e:
        logger.exception("DB query failed")
        return resp(500, {"error": "DB_QUERY_FAILED", "message": str(e)})

    # overlay locks from seat-lock cache
    try:
        r_lock = valkey_client("SEAT_LOCK_CACHE_ENDPOINT", "SEAT_LOCK_CACHE_PORT", "SEAT_LOCK_CACHE_NAME", "seatlock")
    except Exception as e:
        logger.exception("seat-lock cache unavailable")
        return resp(500, {"error": "CACHE_UNAVAILABLE", "message": str(e)})

    # Build lock keys with same tag to allow safe multi-key ops
    lock_keys = [f"seatlock:{tag}:{r['seat_number']}" for r in rows]
    locks = []
    if lock_keys:
        # Safe because all keys share tag -> same slot. [2](https://docs.amazonaws.cn/en_us/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.html)[1](https://docs.amazonaws.cn/en_us/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.Connecting.Python.html)
        locks = r_lock.mget(lock_keys)

    seats_out = []
    as_of = time.strftime("%Y-%m-%dT%H:%M:%S%z")

    for i, r in enumerate(rows):
        seat_id = r["seat_number"]
        status = r["status"]  # AVAILABLE / BOOKED
        lock_val = locks[i] if locks else None

        if status == "AVAILABLE" and lock_val is not None:
            # locked in cache
            ttl_ms = r_lock.pttl(lock_keys[i])
            lock_expires_at = None
            if ttl_ms and ttl_ms > 0:
                lock_expires_at = time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime(time.time() + (ttl_ms / 1000)))

            seats_out.append({
                "seatId": seat_id,
                "row": r.get("seat_row"),
                "number": r.get("seat_no"),
                "status": "LOCKED",
                "lockExpiresAt": lock_expires_at
            })
        else:
            seats_out.append({
                "seatId": seat_id,
                "row": r.get("seat_row"),
                "number": r.get("seat_no"),
                "status": status  # AVAILABLE or BOOKED
            })

    return resp(200, {
        "eventId": event_id,
        "categoryId": category_id,
        "asOf": as_of,
        "seats": seats_out
    })