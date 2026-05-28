import os
import json
import random
import uuid
import base64
import logging
from typing import Any, Dict, Optional

logger = logging.getLogger()
logger.setLevel(logging.INFO)


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


def _get_user_sub_from_rest_api(event: Dict[str, Any]) -> Optional[str]:
    """REST API + Cognito Authorizer (proxy integration): event.requestContext.authorizer.claims"""
    rc = event.get("requestContext") or {}
    auth = rc.get("authorizer") or {}
    claims = auth.get("claims") or {}
    return claims.get("sub")


# ----------------------------
# Handler
# ----------------------------

def handle_payment(event, context):
    user_sub = _get_user_sub_from_rest_api(event)
    if not user_sub:
        return _resp(401, {"error": "UNAUTHORIZED", "message": "Missing Cognito authorizer claims"})

    try:
        body = _parse_json_body(event)
    except Exception:
        return _resp(400, {"error": "INVALID_JSON"})

    reservation_id = body.get("reservationId")
    total_amount = body.get("totalAmount")

    if not reservation_id:
        return _resp(400, {"error": "VALIDATION_ERROR", "message": "reservationId is required"})

    if total_amount is None:
        return _resp(400, {"error": "VALIDATION_ERROR", "message": "totalAmount is required"})

    try:
        total_amount = int(total_amount)
    except (TypeError, ValueError):
        return _resp(400, {"error": "VALIDATION_ERROR", "message": "totalAmount must be an integer"})

    if total_amount < 0:
        return _resp(400, {"error": "VALIDATION_ERROR", "message": "totalAmount must be >= 0"})

    # Determine mock outcome
    mode = os.environ.get("PAYMENT_MOCK_MODE", "always_success").lower()

    if mode == "always_failure":
        should_fail = True
    elif mode == "random":
        try:
            failure_rate = float(os.environ.get("PAYMENT_MOCK_FAILURE_RATE", "0.3"))
            failure_rate = max(0.0, min(1.0, failure_rate))
        except ValueError:
            failure_rate = 0.3
        should_fail = random.random() < failure_rate
    else:
        should_fail = False

    payment_id = str(uuid.uuid4())

    if should_fail:
        logger.info("Mock payment FAILED reservation_id=%s total_amount=%s", reservation_id, total_amount)
        return _resp(402, {
            "paymentId": payment_id,
            "reservationId": reservation_id,
            "status": "FAILED",
            "message": "Payment declined (mock)"
        })

    logger.info("Mock payment SUCCESS reservation_id=%s total_amount=%s", reservation_id, total_amount)
    return _resp(200, {
        "paymentId": payment_id,
        "reservationId": reservation_id,
        "status": "SUCCESS",
        "message": "Payment accepted (mock)"
    })


# ----------------------------
# Main router
# ----------------------------

def handler(event, context):
    path = (event.get("resource") or event.get("path") or "").lower()
    method = (event.get("httpMethod") or "").upper()

    if method == "POST" and path.endswith("/v1/payment"):
        return handle_payment(event, context)

    return _resp(404, {"error": "NOT_FOUND", "message": f"Unsupported route {method} {path}"})
