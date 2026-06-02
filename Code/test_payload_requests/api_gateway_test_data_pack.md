## How to use these

Use these JSON payloads in:

* **Lambda console → Test → Configure test event**, or
* **API Gateway test-style simulation** where  want to mimic the REST proxy event shape.

For the protected endpoints, included a **minimal Cognito authorizer claims block** because  Lambdas read the user identity from `event.requestContext.authorizer.claims.sub`. Without that, the protected routes return `401 UNAUTHORIZED`.

***

# 1) Shared deterministic values used in the test events

Use these values consistently across the test pack. They align with the deterministic IDs from the seed data pack we just updated. 

```text
locationId (Pune)        = 11111111-1111-1111-1111-111111111111
locationId (Mumbai)      = 22222222-2222-2222-2222-222222222222

venueId (Pune)           = 31111111-1111-1111-1111-111111111111
venueId (Mumbai)         = 32222222-2222-2222-2222-222222222222

performerId (Alpha)      = 41111111-1111-1111-1111-111111111111
performerId (Beta)       = 42222222-2222-2222-2222-222222222222

eventId (Pune event)     = 51111111-1111-1111-1111-111111111111
eventId (Mumbai event)   = 52222222-2222-2222-2222-222222222222

categoryId (Pune VIP)    = 61111111-1111-1111-1111-111111111111
categoryId (Pune Gen)    = 62222222-2222-2222-2222-222222222222
categoryId (Mum VIP)     = 63333333-3333-3333-3333-333333333333
categoryId (Mum Gen)     = 64444444-4444-4444-4444-444444444444
```

***

# 2) Protected-route authorizer stub

Use this `requestContext.authorizer.claims` shape for all protected routes. Your queue, seat availability, reservation, payment, and confirmation handlers all pull `sub` from this location.

```json
{
  "requestContext": {
    "authorizer": {
      "claims": {
        "sub": "demo-user-sub-123",
        "email": "demo.user@example.com"
      }
    }
  }
}
```

***

# 3) Browse service test events (public)

These do **not** require Cognito claims because browse is public and the browse handler works from HTTP method, path, query params, and path params only.
***

## 3.1 `GET /v1/location`

```json
{
  "resource": "/v1/location",
  "path": "/v1/location",
  "httpMethod": "GET",
  "headers": {
    "accept": "application/json"
  },
  "multiValueHeaders": {},
  "queryStringParameters": {
    "page": "1",
    "page_size": "10"
  },
  "multiValueQueryStringParameters": null,
  "pathParameters": null,
  "stageVariables": null,
  "requestContext": {
    "resourcePath": "/v1/location",
    "httpMethod": "GET",
    "path": "/prod/v1/location"
  },
  "body": null,
  "isBase64Encoded": false
}
```

This matches the browse service location-list route and its paged query-string style.

***

## 3.2 `GET /v1/venue`

```json
{
  "resource": "/v1/venue",
  "path": "/v1/venue",
  "httpMethod": "GET",
  "headers": {
    "accept": "application/json"
  },
  "multiValueHeaders": {},
  "queryStringParameters": {
    "location_id": "11111111-1111-1111-1111-111111111111",
    "page": "1",
    "page_size": "10"
  },
  "multiValueQueryStringParameters": null,
  "pathParameters": null,
  "stageVariables": null,
  "requestContext": {
    "resourcePath": "/v1/venue",
    "httpMethod": "GET",
    "path": "/prod/v1/venue"
  },
  "body": null,
  "isBase64Encoded": false
}
```

The venue browse flow is location-driven and uses query-string parameters. 
***

## 3.3 `GET /v1/performers`

```json
{
  "resource": "/v1/performers",
  "path": "/v1/performers",
  "httpMethod": "GET",
  "headers": {
    "accept": "application/json"
  },
  "multiValueHeaders": {},
  "queryStringParameters": {
    "location_id": "11111111-1111-1111-1111-111111111111",
    "page": "1",
    "page_size": "10"
  },
  "multiValueQueryStringParameters": null,
  "pathParameters": null,
  "stageVariables": null,
  "requestContext": {
    "resourcePath": "/v1/performers",
    "httpMethod": "GET",
    "path": "/prod/v1/performers"
  },
  "body": null,
  "isBase64Encoded": false
}
```

This matches the performer-by-location browse pattern. 

***

## 3.4 `GET /v1/events`

### Basic browse

```json
{
  "resource": "/v1/events",
  "path": "/v1/events",
  "httpMethod": "GET",
  "headers": {
    "accept": "application/json"
  },
  "multiValueHeaders": {},
  "queryStringParameters": {
    "location_id": "11111111-1111-1111-1111-111111111111",
    "page": "1",
    "page_size": "10"
  },
  "multiValueQueryStringParameters": null,
  "pathParameters": null,
  "stageVariables": null,
  "requestContext": {
    "resourcePath": "/v1/events",
    "httpMethod": "GET",
    "path": "/prod/v1/events"
  },
  "body": null,
  "isBase64Encoded": false
}
```

### Filtered browse

```json
{
  "resource": "/v1/events",
  "path": "/v1/events",
  "httpMethod": "GET",
  "headers": {
    "accept": "application/json"
  },
  "multiValueHeaders": {},
  "queryStringParameters": {
    "location_id": "11111111-1111-1111-1111-111111111111",
    "venue_id": "31111111-1111-1111-1111-111111111111",
    "performer_id": "41111111-1111-1111-1111-111111111111",
    "page": "1",
    "page_size": "10"
  },
  "multiValueQueryStringParameters": null,
  "pathParameters": null,
  "stageVariables": null,
  "requestContext": {
    "resourcePath": "/v1/events",
    "httpMethod": "GET",
    "path": "/prod/v1/events"
  },
  "body": null,
  "isBase64Encoded": false
}
```

The browse event listing is location-first, with optional venue and performer filters. 

***

## 3.5 `GET /v1/event_detail/{eventId}`

```json
{
  "resource": "/v1/event_detail/{eventId}",
  "path": "/v1/event_detail/51111111-1111-1111-1111-111111111111",
  "httpMethod": "GET",
  "headers": {
    "accept": "application/json"
  },
  "multiValueHeaders": {},
  "queryStringParameters": null,
  "multiValueQueryStringParameters": null,
  "pathParameters": {
    "eventId": "51111111-1111-1111-1111-111111111111"
  },
  "stageVariables": null,
  "requestContext": {
    "resourcePath": "/v1/event_detail/{eventId}",
    "httpMethod": "GET",
    "path": "/prod/v1/event_detail/51111111-1111-1111-1111-111111111111"
  },
  "body": null,
  "isBase64Encoded": false
}
```

This matches the event-detail route shape exposed through API Gateway. 
***

# 4) Queue service test events (protected)

These require `requestContext.authorizer.claims.sub`. Queue enter/poll/release all validate Cognito claims first.

***

## 4.1 `POST /v1/queue/enter`

```json
{
  "resource": "/v1/queue/enter",
  "path": "/v1/queue/enter",
  "httpMethod": "POST",
  "headers": {
    "content-type": "application/json",
    "authorization": "Bearer dummy-jwt-for-shape-only"
  },
  "multiValueHeaders": {},
  "queryStringParameters": null,
  "multiValueQueryStringParameters": null,
  "pathParameters": null,
  "stageVariables": null,
  "requestContext": {
    "resourcePath": "/v1/queue/enter",
    "httpMethod": "POST",
    "path": "/prod/v1/queue/enter",
    "authorizer": {
      "claims": {
        "sub": "demo-user-sub-123",
        "email": "demo.user@example.com"
      }
    }
  },
  "body": "{\"eventId\":\"51111111-1111-1111-1111-111111111111\",\"categoryId\":\"61111111-1111-1111-1111-111111111111\"}",
  "isBase64Encoded": false
}
```

The queue enter handler explicitly expects JSON body with `eventId` and `categoryId`.

***

## 4.2 `POST /v1/queue/poll`

```json
{
  "resource": "/v1/queue/poll",
  "path": "/v1/queue/poll",
  "httpMethod": "POST",
  "headers": {
    "content-type": "application/json",
    "authorization": "Bearer dummy-jwt-for-shape-only"
  },
  "multiValueHeaders": {},
  "queryStringParameters": null,
  "multiValueQueryStringParameters": null,
  "pathParameters": null,
  "stageVariables": null,
  "requestContext": {
    "resourcePath": "/v1/queue/poll",
    "httpMethod": "POST",
    "path": "/prod/v1/queue/poll",
    "authorizer": {
      "claims": {
        "sub": "demo-user-sub-123",
        "email": "demo.user@example.com"
      }
    }
  },
  "body": "{\"eventId\":\"51111111-1111-1111-1111-111111111111\",\"categoryId\":\"61111111-1111-1111-1111-111111111111\",\"sessionId\":\"SESSION-ID-FROM-ENTER\",\"bookingToken\":\"BOOKING-TOKEN-FROM-ENTER-OR-POLL\"}",
  "isBase64Encoded": false
}
```

The queue poll handler reads `eventId`, `categoryId`, `sessionId`, and optional echoed `bookingToken`.

***

## 4.3 `POST /v1/queue/release`

```json
{
  "resource": "/v1/queue/release",
  "path": "/v1/queue/release",
  "httpMethod": "POST",
  "headers": {
    "content-type": "application/json",
    "authorization": "Bearer dummy-jwt-for-shape-only"
  },
  "multiValueHeaders": {},
  "queryStringParameters": null,
  "multiValueQueryStringParameters": null,
  "pathParameters": null,
  "stageVariables": null,
  "requestContext": {
    "resourcePath": "/v1/queue/release",
    "httpMethod": "POST",
    "path": "/prod/v1/queue/release",
    "authorizer": {
      "claims": {
        "sub": "demo-user-sub-123",
        "email": "demo.user@example.com"
      }
    }
  },
  "body": "{\"eventId\":\"51111111-1111-1111-1111-111111111111\",\"categoryId\":\"61111111-1111-1111-1111-111111111111\",\"sessionId\":\"SESSION-ID-FROM-ENTER\"}",
  "isBase64Encoded": false
}
```

Release only needs event/category/session context plus claims.

***

# 5) Seat availability service test event (protected)

The seat availability route is protected and also participates in the booking-token flow. The handler shape expects REST proxy event fields and the route is `GET /v1/event/{eventId}/seats`. 
## 5.1 `GET /v1/event/{eventId}/seats`

```json
{
  "resource": "/v1/event/{eventId}/seats",
  "path": "/v1/event/51111111-1111-1111-1111-111111111111/seats",
  "httpMethod": "GET",
  "headers": {
    "accept": "application/json",
    "authorization": "Bearer dummy-jwt-for-shape-only",
    "x-booking-token": "BOOKING-TOKEN-FROM-QUEUE"
  },
  "multiValueHeaders": {},
  "queryStringParameters": {
    "category_id": "61111111-1111-1111-1111-111111111111",
    "limit": "20"
  },
  "multiValueQueryStringParameters": null,
  "pathParameters": {
    "eventId": "51111111-1111-1111-1111-111111111111"
  },
  "stageVariables": null,
  "requestContext": {
    "resourcePath": "/v1/event/{eventId}/seats",
    "httpMethod": "GET",
    "path": "/prod/v1/event/51111111-1111-1111-1111-111111111111/seats",
    "authorizer": {
      "claims": {
        "sub": "demo-user-sub-123",
        "email": "demo.user@example.com"
      }
    }
  },
  "body": null,
  "isBase64Encoded": false
}
```

This event shape is aligned to the route and to the fact that the service validates auth claims and booking token before exposing seats.

***

# 6) Reservation service test event (protected)

The reservation handler is protected and expects `eventId`, `categoryId`, `seats`, and typically an idempotency key. Most importantly, `seats` should be sent as **seat label strings**, not UUID objects, because the reservation validation query matches `seat_label = ANY(...)` against `public.seats`.

## 6.1 `POST /v1/reserveticket`

```json
{
  "resource": "/v1/reserveticket",
  "path": "/v1/reserveticket",
  "httpMethod": "POST",
  "headers": {
    "content-type": "application/json",
    "authorization": "Bearer dummy-jwt-for-shape-only",
    "x-booking-token": "BOOKING-TOKEN-FROM-QUEUE"
  },
  "multiValueHeaders": {},
  "queryStringParameters": null,
  "multiValueQueryStringParameters": null,
  "pathParameters": null,
  "stageVariables": null,
  "requestContext": {
    "resourcePath": "/v1/reserveticket",
    "httpMethod": "POST",
    "path": "/prod/v1/reserveticket",
    "authorizer": {
      "claims": {
        "sub": "demo-user-sub-123",
        "email": "demo.user@example.com"
      }
    }
  },
  "body": "{\"eventId\":\"51111111-1111-1111-1111-111111111111\",\"categoryId\":\"61111111-1111-1111-1111-111111111111\",\"seats\":[\"VIP-0001\",\"VIP-0002\"],\"idempotencyKey\":\"idem-pune-vip-001\",\"bookingToken\":\"BOOKING-TOKEN-FROM-QUEUE\"}",
  "isBase64Encoded": false
}
```

This is the corrected reservation event shape for the current code path.

***

# 7) Payment service test event (protected)

The payment handler is protected and should receive reservation-level payment context. The earlier test pack’s `returnUrl` was removed because it is not part of the current Lambda contract  shared.

## 7.1 `POST /v1/payment`

```json
{
  "resource": "/v1/payment",
  "path": "/v1/payment",
  "httpMethod": "POST",
  "headers": {
    "content-type": "application/json",
    "authorization": "Bearer dummy-jwt-for-shape-only"
  },
  "multiValueHeaders": {},
  "queryStringParameters": null,
  "multiValueQueryStringParameters": null,
  "pathParameters": null,
  "stageVariables": null,
  "requestContext": {
    "resourcePath": "/v1/payment",
    "httpMethod": "POST",
    "path": "/prod/v1/payment",
    "authorizer": {
      "claims": {
        "sub": "demo-user-sub-123",
        "email": "demo.user@example.com"
      }
    }
  },
  "body": "{\"reservationId\":\"RESERVATION-ID-FROM-RESERVETICKET\",\"amount\":6000,\"currency\":\"INR\"}",
  "isBase64Encoded": false
}
```

This is aligned to the current mock payment step.

***

# 8) Confirmation / booking service test event (protected)

The booking handler is protected and finalizes the durable booking flow after successful payment. Include `reservationId`, `paymentId`, and the booking token. Since  current flow passes booking token through this stage, including it in both header and body is the safest test shape.

## 8.1 `POST /v1/booking`

```json
{
  "resource": "/v1/booking",
  "path": "/v1/booking",
  "httpMethod": "POST",
  "headers": {
    "content-type": "application/json",
    "authorization": "Bearer dummy-jwt-for-shape-only",
    "x-booking-token": "BOOKING-TOKEN-FROM-QUEUE"
  },
  "multiValueHeaders": {},
  "queryStringParameters": null,
  "multiValueQueryStringParameters": null,
  "pathParameters": null,
  "stageVariables": null,
  "requestContext": {
    "resourcePath": "/v1/booking",
    "httpMethod": "POST",
    "path": "/prod/v1/booking",
    "authorizer": {
      "claims": {
        "sub": "demo-user-sub-123",
        "email": "demo.user@example.com"
      }
    }
  },
  "body": "{\"reservationId\":\"RESERVATION-ID-FROM-RESERVETICKET\",\"paymentId\":\"PAYMENT-ID-FROM-PAYMENT\",\"bookingToken\":\"BOOKING-TOKEN-FROM-QUEUE\"}",
  "isBase64Encoded": false
}
```

This matches the durable booking/confirmation stage contract direction we established from the code.

***

# 9) Minimal execution order for live end-to-end testing

These console test events are shape-correct, but some values must come from earlier live steps.

## Order to run

1. `GET /v1/location`
2. `GET /v1/venue`
3. `GET /v1/performers`
4. `GET /v1/events`
5. `GET /v1/event_detail/{eventId}`
6. `POST /v1/queue/enter` → capture `sessionId`, `bookingToken`
7. `POST /v1/queue/poll` until allowed → update `bookingToken` if returned
8. `GET /v1/event/{eventId}/seats`
9. `POST /v1/reserveticket` → capture `reservationId`
10. `POST /v1/payment` → capture `paymentId`
11. `POST /v1/booking` [\[docs.aws.amazon.com\]](https://docs.aws.amazon.com/cognito/latest/developerguide/authorization-endpoint.html)

***

# 10) Important notes

## A) Protected routes need `requestContext.authorizer.claims.sub`

If  omit that, the protected Lambdas return unauthorized. This applies to queue, seats, reservation, payment, and booking.

## B) Reservation uses seat labels

Do **not** send seat UUID objects in the reservation body. The current reservation validation query checks `seat_label = ANY(...)`, so use strings like `VIP-0001`.

## C) These are Lambda/API Gateway proxy-shape test events

These are not raw HTTP request bodies; they are the event objects that  Lambda handlers expect from API Gateway REST proxy integration. The handlers explicitly branch on `resource`, `path`, and `httpMethod`.
***


