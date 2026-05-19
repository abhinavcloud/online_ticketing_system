import os
import json
import time
import uuid
import base64
import logging
from typing import Any, Dict, Optional, Tuple

import boto3

try:
    import redis  # redis-py
except Exception:  # pragma: no cover
    redis = None

from botocore.session import Session
from botocore.auth import SigV4QueryAuth
from botocore.awsrequest import AWSRequest


logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Warm container cache for redis client + IAM token
_VALKEY = None
_VALKEY_REFRESH_AT = 0.0


# ----------------------------
# Responses / parsing
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
    """
    REST API + Cognito Authorizer (proxy integration) exposes claims at:
      event.requestContext.author
    [1](https://stackoverflow.com/questions/71199379/how-to-pass-cognito-user-pool-information-to-lambda-through-api-gateway)[2](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html)
    """
    rc = event.get("requestContext") or {}
    auth = rc.get("authorizer") or {}
    claims = auth.get("claims") or {}
    return claims.get("sub")


# ----------------------------
# ElastiCache Serverless IAM auth (Valkey/Redis)
# ----------------------------
def _elasticache_iam_token(user_id: str, cache_name: str, region: str) -> str:
    """
    IAM auth token is a SigV4 presigned URL, used as password.
    - Requires TLS
    - Cache name should be lowercase
    - IAM-enabled ElastiCache users require username == user_id
    [3](https://awstip.com/creating-aws-lambda-layers-for-python-runtime-a-complete-guide-93c307a71dd3)
    """
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
        expires=900,  # 15 minutes
    )
    signer.add_auth(aws_req)

    return aws_req.url.replace("http://", "")


def _active_users_cache_client():
    global _VALKEY, _VALKEY_REFRESH_AT

    if redis is None:
        raise RuntimeError("redis library not available. Add redis to your layer/package.")

    endpoint = os.environ["ACTIVE_USERS_CACHE_ENDPOINT"]
    port = int(os.environ.get("ACTIVE_USERS_CACHE_PORT", "6379"))
    cache_name = os.environ["ACTIVE_USERS_CACHE_NAME"]  # e.g., "active-users"
    user_id = os.environ["ELASTICACHE_USER_ID"]
    region = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION")

    now = time.time()
    if _VALKEY is not None and now < _VALKEY_REFRESH_AT:
        return _VALKEY

    token = _elasticache_iam_token(user_id=user_id, cache_name=cache_name, region=region)

    client = redis.Redis(
        host=endpoint,
        port=port,
        username=user_id,
        password=token,
        ssl=True,            # IAM auth requires TLS [3](https://awstip.com/creating-aws-lambda-layers-for-python-runtime-a-complete-guide-93c307a71dd3)
        ssl_cert_reqs=None,
        decode_responses=True,
        socket_connect_timeout=2,
        socket_timeout=2,
    )
    client.ping()

    _VALKEY = client
    _VALKEY_REFRESH_AT = now + (14 * 60)
    return client


# ----------------------------
# JWT via KMS (RS256-style)
# ----------------------------
def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("utf-8").rstrip("=")


def _kms_sign_rs256(message: bytes, key_id: str) -> bytes:
    kms = boto3.client("kms")
    # For RSA_2048 SIGN_VERIFY keys:
    # Use RSASSA_PKCS1_V1_5_SHA_256
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

    header = {
        "alg": "RS256",
        "typ": "JWT",
        # Optional: include KMS key id as kid (makes verification simpler later)
        "kid": key_id,
    }
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

    signing_input = f"{_b64url(json.dumps(header, separators=(',', ':')).encode())}.{_b64url(json.dumps(payload, separators=(',', ':')).encode())}".encode()
    sig = _kms_sign_rs256(signing_input, key_id=key_id)
    token = f"{signing_input.decode()}.{_b64url(sig)}"
    return token


# ----------------------------
# Queue logic
# ----------------------------
def _env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, str(default)))
    except Exception:
        return default


def handler(event, context):
    # Validate auth
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
    if not event_id or not category_id:
        return _resp(400, {"error": "VALIDATION_ERROR", "message": "eventId and categoryId are required"})

    # Config
    allowed_ttl = _env_int("QUEUE_ALLOWED_TTL_SECONDS", 600)
    poll_after = _env_int("QUEUE_POLL_AFTER_SECONDS", 5)
    oversell_factor = _env_int("QUEUE_OVERSELL_FACTOR", 2)
    max_active = _env_int("QUEUE_MAX_USERS_PER_EVENT_CATEGORY", 0)  # 0 means "no explicit cap"

    jwt_kms_key_id = os.environ["JWT_KMS_KEY_ID"]
    jwt_issuer = os.environ.get("JWT_ISSUER", "ticketing-queue")

    # Keys
    base = f"{event_id}:{category_id}"
    waiting_key = f"queue:waiting:{base}"     # ZSET(sessionId -> enqueue_ts)
    allowed_key = f"queue:allowed:{base}"     # SET(sessionId), TTL
    active_key = f"queue:active_count:{base}" # STRING counter
    soldout_key = f"queue:soldout:{base}"     # STRING flag
    session_key = f"queue:session:{base}:"    # prefix + sessionId

    # Connect cache
    try:
        r = _active_users_cache_client()
    except Exception as e:
        logger.exception("Active-users cache unavailable")
        return _resp(500, {"error": "CACHE_UNAVAILABLE", "message": str(e)})

    # SOLD_OUT short-circuit (optional flag you can set later from ops/admin)
    if r.get(soldout_key) == "1":
        return _resp(200, {
            "status": "SOLD_OUT",
            "bookingToken": None,
            "sessionId": None,
            "expiresInSeconds": allowed_ttl,
            "pollAfterSeconds": poll_after,
            "message": "Tickets are sold out for this category."
        })

    # Create new sessionId per enter call (idempotency can be added later if needed)
    session_id = str(uuid.uuid4())
    enqueue_ts = int(time.time())

    # Basic admission rule:
    # - If max_active is set and active_count >= max_active => WAITING
    # - Else ALLOWED (and increment active_count), with TTL lease.
    # oversell_factor can be used later when you have seat inventory per category.
    #
    # For now, oversell_factor is a knob kept for parity with your design;
    # we are not using it until seat inventory is wired in.
    try:
        pipe = r.pipeline(transaction=True)

        # ensure base keys exist
        pipe.incrby(active_key, 0)  # initialize read
        res = pipe.execute()
        active_count = int(res[0] or 0)

        if max_active > 0 and active_count >= max_active:
            # WAITING: add to ZSET
            pipe = r.pipeline(transaction=True)
            pipe.zadd(waiting_key, {session_id: enqueue_ts})
            pipe.expire(waiting_key, allowed_ttl)
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

            # store session meta (optional but useful)
            r.setex(f"{session_key}{session_id}", allowed_ttl, json.dumps({
                "status": "WAITING",
                "userSub": user_sub,
                "eventId": event_id,
                "categoryId": category_id,
                "createdAt": enqueue_ts,
            }))

            return _resp(200, {
                "status": "WAITING",
                "bookingToken": token,
                "sessionId": session_id,
                "expiresInSeconds": allowed_ttl,
                "pollAfterSeconds": poll_after,
                "message": "Please wait while we get you available seats."
            })

        # ALLOWED: add to allowed set (lease with TTL) and increment active count
        pipe = r.pipeline(transaction=True)
        pipe.sadd(allowed_key, session_id)
        pipe.expire(allowed_key, allowed_ttl)
        pipe.incr(active_key)
        pipe.expire(active_key, allowed_ttl)
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

        r.setex(f"{session_key}{session_id}", allowed_ttl, json.dumps({
            "status": "ALLOWED",
            "userSub": user_sub,
            "eventId": event_id,
            "categoryId": category_id,
            "createdAt": enqueue_ts,
        }))

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
