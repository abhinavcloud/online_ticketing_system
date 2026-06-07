import os
import json
import time
import uuid
import base64
import logging
from typing import Any, Dict, List, Optional, Tuple

import boto3

try:
    import redis
except Exception:  # pragma: no cover
    redis = None

try:
    import psycopg2
except Exception:  # pragma: no cover
    psycopg2 = None

from botocore.session import Session
from botocore.auth import SigV4QueryAuth
from botocore.awsrequest import AWSRequest
from botocore.config import Config

logger = logging.getLogger()
logger.setLevel(logging.INFO)

_BOTO_CFG = Config(connect_timeout=45, read_timeout=3, retries={"max_attempts": 1})

# ----------------------------
# Warm caches
# ----------------------------
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
    """Verify the Queue-issued bookingToken JWT using KMS Verify."""
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


def _seatlock_cache():
    """Seat-lock cache (Valkey)."""
    global _SEATLOCK_REDIS, _SEATLOCK_REDIS_REFRESH_AT

    if redis is None:
        raise RuntimeError("redis library not available.")

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
        raise RuntimeError("psycopg2 not available.")

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
# Key helpers (cluster-safe, same conventions as reservation service)
# ----------------------------

def _tag(event_id: str, category_id: str) -> str:
    return f"{{{event_id}:{category_id}}}"


def _seat_lock_key(event_id: str, category_id: str, seat_id: str) -> str:
    tag = _tag(event_id, category_id)
    return f"seatlock:{tag}:{seat_id}"


def _reservation_seats_key(event_id: str, category_id: str, reservation_id: str) -> str:
    tag = _tag(event_id, category_id)
    return f"reservation:{tag}:{reservation_id}:seats"


def _reservation_meta_key(event_id: str, category_id: str, reservation_id: str) -> str:
    tag = _tag(event_id, category_id)
    return f"reservation:{tag}:{reservation_id}:meta"


def _reservation_lookup_key(reservation_id: str) -> str:
    return f"reservation:lookup:{reservation_id}"


def _seats_lock_count_key(event_id: str, category_id: str) -> str:
    tag = _tag(event_id, category_id)
    return f"seatlock:{tag}:locked_count"


# ----------------------------
# Lua: verify all seat locks still exist (atomic check, all-or-nothing)
# KEYS[1..N]: seat lock keys
# Returns {1, ''} if all exist, {0, missing_key} if any is missing
# ----------------------------

_CHECK_ALL_LOCKS_LUA = r"""
local expected = ARGV[1]
for i = 1, #KEYS do
    local v = redis.call('GET', KEYS[i])
    if not v then
        return {0, KEYS[i]}
    end
    if v ~= expected then
        return {0, KEYS[i]}
    end
end

return {1, ''}
"""

_RELEASE_LOCKS_LUA = r"""
local res_id    = ARGV[1]
local count_key = KEYS[#KEYS]
local deleted = 0

for i = 1, #KEYS - 1 do
    local v = redis.call('GET', KEYS[i])
    if v and v == res_id then
        redis.call('DEL', KEYS[i])
        deleted = deleted + 1
    end
end

if deleted > 0 then
    local new_val = redis.call('DECRBY', count_key, deleted)
    if int(new_val) < 0 then
        redis.call('SET', count_key, 0)
    end
end

return deleted
"""

# ----------------------------
# Cache helpers
# ----------------------------

def _delete_locks_best_effort(sl, keys: List[str]) -> None:
    if not keys:
        return
    try:
        sl.delete(*keys)
    except Exception:
        logger.exception("Failed to delete seat locks (best-effort)")


def _delete_locks_and_decrement(sl, lock_keys: List[str], count_key: str, reservation_id: str) -> None:
    if not lock_keys:
        return
    try:
        all_keys = lock_keys + [count_key]
        sl.eval(_RELEASE_LOCKS_LUA, len(all_keys) + 1, *all_keys, reservation_id)
    except Exception:
        logger.exception("Failed to delete seat locks and decrement count (best-effort)")

# ----------------------------
# Notification (SNS, best-effort)
# ----------------------------

def _notify_best_effort(payload: Dict[str, Any]) -> None:
    topic_arn = os.environ.get("NOTIFICATION_TOPIC_ARN")
    if not topic_arn:
        logger.warning("NOTIFICATION_TOPIC_ARN not set; skipping notification")
        return
    try:
        sns = boto3.client("sns", config=_BOTO_CFG)
        sns.publish(
            TopicArn=topic_arn,
            Message=json.dumps(payload, default=str),
            Subject=payload.get("type", "BOOKING_EVENT"),
        )
    except Exception:
        logger.exception("Notification publish failed (best-effort)")


# ----------------------------
# DB functions
# ----------------------------

def _fetch_event_details(event_id: str, category_id: str) -> Dict[str, Any]:
    """Fetch denormalized event + venue + category details for ticket creation.

    Assumed schema:
    public.events(id, name, event_date, event_time, venue_id)
    public.venues(id, name, address)
    public.event_categories(id, event_id, name, price, currency)
    """
    global _DB_CONN, _DB_CONN_REFRESH_AT

    sql = """
        SELECT
            e.name           AS event_name,
            e.event_date,
            e.event_time,
            v.id             AS venue_id,
            v.name           AS venue_name,
            v.address        AS venue_address,
            ec.name          AS category_name,
            ec.price         AS unit_price,
            ec.currency
        FROM public.events e
        JOIN public.venues v ON v.id = e.venue_id
        JOIN public.event_categories ec ON ec.id = %s AND ec.event_id = e.id
        WHERE e.id = %s
    """
    for attempt in range(2):
        try:
            conn = _db_conn()
            with conn.cursor() as cur:
                cur.execute(sql, (category_id, event_id))
                row = cur.fetchone()
            if not row:
                raise ValueError(f"Event or category not found: event_id={event_id} category_id={category_id}")
            return {
                "eventName":    row[0],
                "eventDate":    row[1],
                "eventTime":    row[2],
                "venueId":      str(row[3]),
                "venueName":    row[4],
                "venueAddress": row[5],
                "categoryName": row[6],
                "unitPrice":    int(row[7]),
                "currency":     str(row[8]),
            }
        except psycopg2.OperationalError:
            if attempt == 0:
                _DB_CONN = None
                _DB_CONN_REFRESH_AT = 0.0
            else:
                raise


def _validate_seats_available_db(event_id: str, category_id: str, seat_ids: List[str]) -> None:
    """Confirm all seats are still AVAILABLE in DB before committing the booking."""
    global _DB_CONN, _DB_CONN_REFRESH_AT

    sql = """
        SELECT seat_label
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
                found = {row[0] for row in cur.fetchall()}
            missing = [s for s in seat_ids if s not in found]
            if missing:
                raise ValueError(f"Seats no longer AVAILABLE in DB: {missing}")
            return
        except psycopg2.OperationalError:
            if attempt == 0:
                _DB_CONN = None
                _DB_CONN_REFRESH_AT = 0.0
            else:
                raise


def _book_seats_and_insert_tickets(
    user_id: str,
    reservation_id: str,
    payment_id: str,
    event_id: str,
    category_id: str,
    seat_ids: List[str],
    total_amount: int,
    event_details: Dict[str, Any],
) -> List[str]:
    """Atomically update seats to BOOKED and insert one ticket row per seat.

    Returns list of generated ticket IDs.
    Raises on any failure; caller must handle compensation.

    Assumed tickets schema:
    public.tickets(
        id UUID, user_id TEXT, reservation_id UUID, payment_id UUID,
        event_id UUID, category_id UUID, venue_id UUID, seat_label TEXT,
        unit_price INTEGER, total_amount INTEGER, currency TEXT,
        event_name TEXT, event_date DATE, event_time TIME,
        venue_name TEXT, venue_address TEXT, category_name TEXT,
        status TEXT, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ
    )
    """
    global _DB_CONN, _DB_CONN_REFRESH_AT

    for attempt in range(2):
        try:
            conn = _db_conn()
            with conn.cursor() as cur:
                cur.execute("BEGIN;")
                try:
                    # Lock and update seats to BOOKED
                    cur.execute(
                        """
                        UPDATE public.seats
                        SET status = 'BOOKED', updated_at = now()
                        WHERE event_id = %s
                        AND category_id = %s
                        AND seat_label = ANY(%s)
                        AND status = 'AVAILABLE'
                        """,
                        (event_id, category_id, seat_ids),
                    )
                    updated = cur.rowcount
                    if updated != len(seat_ids):
                        cur.execute("ROLLBACK;")
                        raise ValueError(
                            f"Expected to book {len(seat_ids)} seats but only {updated} were AVAILABLE"
                        )

                    # Insert one ticket per seat
                    ticket_ids = []
                    for seat_label in seat_ids:
                        ticket_id = str(uuid.uuid4())
                        ticket_ids.append(ticket_id)
                        cur.execute(
                            """
                            INSERT INTO public.tickets (
                                id, user_id, reservation_id, payment_id,
                                event_id, category_id, venue_id, seat_label,
                                unit_price, total_amount, currency,
                                event_name, event_date, event_time,
                                venue_name, venue_address, category_name,
                                status, created_at, updated_at
                            ) VALUES (
                                %s, %s, %s, %s,
                                %s, %s, %s, %s,
                                %s, %s, %s,
                                %s, %s, %s,
                                %s, %s, %s,
                                'CONFIRMED', now(), now()
                            )
                            """,
                            (
                                ticket_id, user_id, reservation_id, payment_id,
                                event_id, category_id, event_details["venueId"], seat_label,
                                event_details["unitPrice"], total_amount, event_details["currency"],
                                event_details["eventName"], event_details["eventDate"], event_details["eventTime"],
                                event_details["venueName"], event_details["venueAddress"], event_details["categoryName"],
                            ),
                        )

                    cur.execute("COMMIT;")
                    return ticket_ids

                except Exception:
                    try:
                        cur.execute("ROLLBACK;")
                    except Exception:
                        pass
                    raise

        except psycopg2.OperationalError:
            if attempt == 0:
                _DB_CONN = None
                _DB_CONN_REFRESH_AT = 0.0
            else:
                raise


# ----------------------------
# Booking handler
# ----------------------------

def handle_booking(event, context):
    user_sub = _get_user_sub_from_rest_api(event)
    if not user_sub:
        return _resp(401, {"error": "UNAUTHORIZED", "message": "Missing Cognito authorizer claims"})

    try:
        body = _parse_json_body(event)
    except Exception:
        return _resp(400, {"error": "INVALID_JSON"})

    reservation_id = body.get("reservationId")
    payment_id = body.get("paymentId")
    payment_status = body.get("paymentStatus")
    paid_at = body.get("paidAt")
    amount = body.get("amount")

    if not reservation_id or not payment_id or not payment_status:
        return _resp(400, {
            "error": "VALIDATION_ERROR",
            "message": "reservationId, paymentId and paymentStatus are required"
        })

    if payment_status != "SUCCESS":
        return _resp(402, {
            "reservationId": reservation_id,
            "status": "FAILED",
            "reason": "PAYMENT_NOT_SUCCESS",
            "message": "Payment was not successful"
        })

    if amount is not None:
        try:
            amount = int(amount)
        except (TypeError, ValueError):
            return _resp(400, {
                "error": "VALIDATION_ERROR",
                "message": "amount must be an integer if provided"
        })

    # Verify booking token
    h = _headers_lc(event)
    booking_token = h.get("x-booking-token") or h.get("authorization")
    if booking_token and booking_token.lower().startswith("bearer "):
        booking_token = booking_token.split(" ", 1)[1].strip()

    if not booking_token:
        return _resp(400, {"error": "MISSING_BOOKING_TOKEN", "message": "x-booking-token header required"})

    try:
        bt = _verify_booking_token(booking_token)
    except Exception as e:
        return _resp(401, {"error": "INVALID_BOOKING_TOKEN", "message": str(e)})

    if bt.get("sub") != user_sub:
        return _resp(403, {"error": "TOKEN_USER_MISMATCH"})
    if bt.get("scope") != "booking:queue":
        return _resp(401, {"error": "INVALID_BOOKING_TOKEN", "message": "invalid token scope"})

    # Connect to seat lock cache
    try:
        sl = _seatlock_cache()
    except Exception as e:
        logger.exception("Seat-lock cache unavailable")
        return _resp(500, {"error": "SEAT_LOCK_CACHE_UNAVAILABLE", "message": str(e)})

    # Resolve eventId and categoryId from the lookup key written by the reservation service
    lookup_raw = sl.get(_reservation_lookup_key(reservation_id))
    if not lookup_raw:
        _notify_best_effort({
            "type": "BOOKING_FAILED",
            "userId": user_sub,
            "reservationId": reservation_id,
            "paymentId": payment_id,
            "reason": "RESERVATION_EXPIRED",
        })
        return _resp(409, {
            "reservationId": reservation_id,
            "status": "FAILED",
            "reason": "RESERVATION_EXPIRED",
            "message": "Reservation has expired. Payment refund is not handled by this service."
        })

    lookup = json.loads(lookup_raw)
    event_id = lookup.get("eventId")
    category_id = lookup.get("categoryId")

    if not event_id or not category_id:
        return _resp(500, {"error": "RESERVATION_LOOKUP_CORRUPT", "message": "Reservation lookup missing eventId or categoryId"})

    # Verify token eventId/categoryId match what the reservation service stored
    if bt.get("eventId") != event_id or bt.get("categoryId") != category_id:
        return _resp(403, {"error": "TOKEN_SCOPE_MISMATCH"})

    # Read seat IDs and meta from cache (written atomically by reservation service)
    seats_key = _reservation_seats_key(event_id, category_id, reservation_id)
    meta_key = _reservation_meta_key(event_id, category_id, reservation_id)

    seats_raw = sl.get(seats_key)
    meta_raw = sl.get(meta_key)

    if not seats_raw or not meta_raw:
        _notify_best_effort({
            "type": "BOOKING_FAILED",
            "userId": user_sub,
            "reservationId": reservation_id,
            "paymentId": payment_id,
            "eventId": event_id,
            "categoryId": category_id,
            "reason": "RESERVATION_EXPIRED",
        })
        return _resp(409, {
            "reservationId": reservation_id,
            "status": "FAILED",
            "reason": "RESERVATION_EXPIRED",
            "message": "Reservation has expired. Payment refund is not handled by this service."
        })

    seat_ids = json.loads(seats_raw)
    meta = json.loads(meta_raw)
    total_amount = int(meta.get("totalAmount", 0))
    
    if amount is not None and amount != total_amount:
        return _resp(409, {
            "reservationId": reservation_id,
            "status": "FAILED",
            "reason": "AMOUNT_MISMATCH",
            "message": f"Amount mismatch. Expected {total_amount}, got {amount}"
        })


    # Build seat lock keys and the shared counter key
    lock_keys = [_seat_lock_key(event_id, category_id, sid) for sid in seat_ids]
    count_key = _seats_lock_count_key(event_id, category_id)

    # Check all seat locks still exist in cache (atomic Lua)
    try:
        ok, missing_key = sl.eval(_CHECK_ALL_LOCKS_LUA, len(lock_keys), *lock_keys, reservation_id )
        ok = int(ok)
    except Exception as e:
        logger.exception("Seat lock check Lua failed")
        return _resp(500, {"error": "SEAT_LOCK_CHECK_FAILED", "message": str(e)})

    if ok != 1:
        # At least one lock is gone — delete all remaining locks and fail
        _delete_locks_and_decrement(sl, lock_keys, count_key, reservation_id)
        _notify_best_effort({
            "type": "BOOKING_FAILED",
            "userId": user_sub,
            "reservationId": reservation_id,
            "paymentId": payment_id,
            "eventId": event_id,
            "categoryId": category_id,
            "seats": seat_ids,
            "reason": "SEAT_LOCK_EXPIRED",
        })
        return _resp(409, {
            "reservationId": reservation_id,
            "status": "FAILED",
            "reason": "SEAT_LOCK_EXPIRED",
            "message": f"eat lock invalid or expired for key: {missing_key}. Payment refund will be handled seperately."
        })

    # Validate seats are still AVAILABLE in DB
    try:
        _validate_seats_available_db(event_id, category_id, seat_ids)
    except Exception as e:
        _delete_locks_and_decrement(sl, lock_keys, count_key, reservation_id)
        _notify_best_effort({
            "type": "BOOKING_FAILED",
            "userId": user_sub,
            "reservationId": reservation_id,
            "paymentId": payment_id,
            "eventId": event_id,
            "categoryId": category_id,
            "seats": seat_ids,
            "reason": "SEAT_NOT_AVAILABLE_DB",
        })
        return _resp(409, {
            "reservationId": reservation_id,
            "status": "FAILED",
            "reason": "SEAT_NOT_AVAILABLE_DB",
            "message": str(e)
        })

    # Fetch event + venue + category details for ticket creation
    try:
        event_details = _fetch_event_details(event_id, category_id)
    except Exception as e:
        logger.exception("Event details fetch failed")
        _delete_locks_and_decrement(sl, lock_keys, count_key, reservation_id)
        _notify_best_effort({
            "type": "BOOKING_FAILED",
            "userId": user_sub,
            "reservationId": reservation_id,
            "paymentId": payment_id,
            "eventId": event_id,
            "categoryId": category_id,
            "seats": seat_ids,
            "reason": "EVENT_DETAILS_FETCH_FAILED",
        })
        return _resp(500, {
            "reservationId": reservation_id,
            "status": "FAILED",
            "reason": "EVENT_DETAILS_FETCH_FAILED",
            "message": str(e)
        })

    # Atomically update seats to BOOKED and insert tickets
    try:
        ticket_ids = _book_seats_and_insert_tickets(
            user_id=user_sub,
            reservation_id=reservation_id,
            payment_id=payment_id,
            event_id=event_id,
            category_id=category_id,
            seat_ids=seat_ids,
            total_amount=total_amount,
            event_details=event_details,
        )
    except Exception as e:
        logger.exception("DB booking transaction failed")
        _delete_locks_and_decrement(sl, lock_keys, count_key, reservation_id)
        _notify_best_effort({
            "type": "BOOKING_FAILED",
            "userId": user_sub,
            "reservationId": reservation_id,
            "paymentId": payment_id,
            "eventId": event_id,
            "categoryId": category_id,
            "seats": seat_ids,
            "reason": "DB_BOOKING_FAILED",
        })
        return _resp(500, {
            "reservationId": reservation_id,
            "status": "FAILED",
            "reason": "DB_BOOKING_FAILED",
            "message": str(e)
        })

    # Booking confirmed — release seat locks and lookup key from cache
    _delete_locks_and_decrement(sl, lock_keys, count_key, reservation_id)
    try:
        sl.delete(
            _reservation_lookup_key(reservation_id),
            seats_key,
            meta_key
        )

    except Exception:
        logger.exception("Failed to delete reservation lookup key (best-effort)")

    _notify_best_effort({
        "type": "BOOKING_SUCCESS",
        "userId": user_sub,
        "reservationId": reservation_id,
        "paymentId": payment_id,
        "eventId": event_id,
        "categoryId": category_id,
        "seats": seat_ids,
        "ticketIds": ticket_ids,
        "totalAmount": total_amount,
        "currency": event_details["currency"],
        "eventName": event_details["eventName"],
        "eventDate": str(event_details["eventDate"]),
        "eventTime": str(event_details["eventTime"]),
        "venueName": event_details["venueName"],
        "venueAddress": event_details["venueAddress"],
    })

    return _resp(200, {
        "reservationId": reservation_id,
        "status": "CONFIRMED",
        "paymentId": payment_id,
        "ticketIds": ticket_ids,
        "eventId": event_id,
        "categoryId": category_id,
        "seats": seat_ids,
        "pricing": {
            "totalAmount": total_amount,
            "currency": event_details["currency"],
        },
        "event": {
            "name": event_details["eventName"],
            "date": str(event_details["eventDate"]),
            "time": str(event_details["eventTime"]),
            "venue": event_details["venueName"],
            "address": event_details["venueAddress"],
            "category": event_details["categoryName"],
        }
    })


# ----------------------------
# Main router
# ----------------------------

def handler(event, context):
    path = (event.get("resource") or event.get("path") or "").lower()
    method = (event.get("httpMethod") or "").upper()

    if method == "POST" and path.endswith("/v1/booking"):
        return handle_booking(event, context)

    return _resp(404, {"error": "NOT_FOUND", "message": f"Unsupported route {method} {path}"})
