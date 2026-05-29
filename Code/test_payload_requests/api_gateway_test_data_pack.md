# API Gateway Test Data Pack

This pack gives you **deterministic DB test data** plus **request templates** for every API Gateway resource/method currently visible in your Terraform:

- `GET /v1/location`
- `GET /v1/venue`
- `GET /v1/performers`
- `GET /v1/events`
- `GET /v1/event_detail/{eventId}`
- `POST /v1/queue/enter`
- `POST /v1/queue/poll`
- `POST /v1/queue/release`
- `GET /v1/event/{eventId}/seats`
- `POST /v1/reserveticket`
- `POST /v1/payment`
- `POST /v1/booking`

---

## 1) Deterministic SQL seed data

Paste this whole SQL block into `psql` connected to `onlineticketingsystem`.

```sql
BEGIN;

-- Optional cleanup for repeatable test setup
DELETE FROM public.tickets;
DELETE FROM public.reservation_seats;
DELETE FROM public.reservations;
DELETE FROM public.seats;
DELETE FROM public.event_categories;
DELETE FROM public.event_performers;
DELETE FROM public.events;
DELETE FROM public.performers;
DELETE FROM public.venues;
DELETE FROM public.locations;

-- -----------------------------------------------------------------------------
-- Locations
-- -----------------------------------------------------------------------------
INSERT INTO public.locations (id, name)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'Pune'),
  ('22222222-2222-2222-2222-222222222222', 'Mumbai')
ON CONFLICT (id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Venues
-- -----------------------------------------------------------------------------
INSERT INTO public.venues (id, location_id, name, address)
VALUES
  ('31111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'Pune Grand Arena', 'Hinjewadi Phase 1, Pune'),
  ('32222222-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222', 'Mumbai Harbour Dome', 'BKC, Mumbai')
ON CONFLICT (id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Performers
-- -----------------------------------------------------------------------------
INSERT INTO public.performers (id, name)
VALUES
  ('41111111-1111-1111-1111-111111111111', 'Artist Alpha'),
  ('42222222-2222-2222-2222-222222222222', 'Artist Beta')
ON CONFLICT (id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Events
-- -----------------------------------------------------------------------------
INSERT INTO public.events (id, name, description, venue_id, event_date, event_time, event_type, status)
VALUES
  (
    '51111111-1111-1111-1111-111111111111',
    'Pune Live Night',
    'Primary event used for queue, seat, reservation, payment and booking tests',
    '31111111-1111-1111-1111-111111111111',
    '2030-01-10 19:00:00+05:30',
    '19:00:00',
    'Concert',
    'ON_SALE'
  ),
  (
    '52222222-2222-2222-2222-222222222222',
    'Mumbai Comedy Evening',
    'Secondary event used for browse endpoint filtering tests',
    '32222222-2222-2222-2222-222222222222',
    '2030-01-15 20:00:00+05:30',
    '20:00:00',
    'Comedy',
    'ON_SALE'
  )
ON CONFLICT (id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Event / Performer mappings
-- -----------------------------------------------------------------------------
INSERT INTO public.event_performers (event_id, performer_id)
VALUES
  ('51111111-1111-1111-1111-111111111111', '41111111-1111-1111-1111-111111111111'),
  ('52222222-2222-2222-2222-222222222222', '42222222-2222-2222-2222-222222222222')
ON CONFLICT DO NOTHING;

-- -----------------------------------------------------------------------------
-- Event categories
-- -----------------------------------------------------------------------------
INSERT INTO public.event_categories (id, event_id, name, price, currency)
VALUES
  ('61111111-1111-1111-1111-111111111111', '51111111-1111-1111-1111-111111111111', 'VIP',     3000, 'INR'),
  ('62222222-2222-2222-2222-222222222222', '51111111-1111-1111-1111-111111111111', 'General',  500, 'INR'),
  ('63333333-3333-3333-3333-333333333333', '52222222-2222-2222-2222-222222222222', 'VIP',     2500, 'INR'),
  ('64444444-4444-4444-4444-444444444444', '52222222-2222-2222-2222-222222222222', 'General',  700, 'INR')
ON CONFLICT (id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Seats for Event 1 (Pune Live Night)
-- 20 VIP seats + 20 General seats are enough for endpoint testing.
-- -----------------------------------------------------------------------------
INSERT INTO public.seats (id, event_id, category_id, seat_label, status)
SELECT
  gen_random_uuid(),
  '51111111-1111-1111-1111-111111111111',
  '61111111-1111-1111-1111-111111111111',
  'VIP-' || lpad(gs::text, 4, '0'),
  'AVAILABLE'::seat_status
FROM generate_series(1, 20) gs
ON CONFLICT (event_id, seat_label) DO NOTHING;

INSERT INTO public.seats (id, event_id, category_id, seat_label, status)
SELECT
  gen_random_uuid(),
  '51111111-1111-1111-1111-111111111111',
  '62222222-2222-2222-2222-222222222222',
  'GEN-' || lpad(gs::text, 4, '0'),
  'AVAILABLE'::seat_status
FROM generate_series(1, 20) gs
ON CONFLICT (event_id, seat_label) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Seats for Event 2 (Mumbai Comedy Evening)
-- -----------------------------------------------------------------------------
INSERT INTO public.seats (id, event_id, category_id, seat_label, status)
SELECT
  gen_random_uuid(),
  '52222222-2222-2222-2222-222222222222',
  '63333333-3333-3333-3333-333333333333',
  'VIP-' || lpad(gs::text, 4, '0'),
  'AVAILABLE'::seat_status
FROM generate_series(1, 20) gs
ON CONFLICT (event_id, seat_label) DO NOTHING;

INSERT INTO public.seats (id, event_id, category_id, seat_label, status)
SELECT
  gen_random_uuid(),
  '52222222-2222-2222-2222-222222222222',
  '64444444-4444-4444-4444-444444444444',
  'GEN-' || lpad(gs::text, 4, '0'),
  'AVAILABLE'::seat_status
FROM generate_series(1, 20) gs
ON CONFLICT (event_id, seat_label) DO NOTHING;

COMMIT;
```

---

## 2) Fixed IDs you can directly use in API tests

```text
locationId (Pune)      = 11111111-1111-1111-1111-111111111111
locationId (Mumbai)    = 22222222-2222-2222-2222-222222222222

venueId (Pune)         = 31111111-1111-1111-1111-111111111111
venueId (Mumbai)       = 32222222-2222-2222-2222-222222222222

performerId (Alpha)    = 41111111-1111-1111-1111-111111111111
performerId (Beta)     = 42222222-2222-2222-2222-222222222222

eventId (Pune event)   = 51111111-1111-1111-1111-111111111111
eventId (Mumbai event) = 52222222-2222-2222-2222-222222222222

categoryId (Pune VIP)  = 61111111-1111-1111-1111-111111111111
categoryId (Pune Gen)  = 62222222-2222-2222-2222-222222222222
categoryId (Mum VIP)   = 63333333-3333-3333-3333-333333333333
categoryId (Mum Gen)   = 64444444-4444-4444-4444-444444444444
```

---

## 3) SQL to fetch actual seat IDs for reservation tests

Use this after seeding. Pick any 2 seat IDs from the result.

```sql
SELECT id, seat_label, status
FROM public.seats
WHERE event_id = '51111111-1111-1111-1111-111111111111'
  AND category_id = '61111111-1111-1111-1111-111111111111'
  AND status = 'AVAILABLE'
ORDER BY seat_label
LIMIT 5;
```

---

## 4) Endpoint-by-endpoint request templates

Set your base URL first:

```bash
export BASE_URL="https://<api-id>.execute-api.<region>.amazonaws.com/<stage>/v1"
export JWT="<cognito-jwt>"
export BOOKING_TOKEN="<queue-issued-booking-token>"
export SESSION_ID="<queue-session-id>"
export RESERVATION_ID="<reservation-id-from-reserveticket-response>"
export PAYMENT_ID="<payment-id-from-payment-response>"
export SEAT_ID_1="<seat-id-from-seat-query>"
export SEAT_ID_2="<seat-id-from-seat-query>"
```

### 4.1 `GET /v1/location`

```bash
curl -s "${BASE_URL}/location?page=1&page_size=10"
```

### 4.2 `GET /v1/venue`

```bash
curl -s "${BASE_URL}/venue?location_id=11111111-1111-1111-1111-111111111111&page=1&page_size=10"
```

### 4.3 `GET /v1/performers`

```bash
curl -s "${BASE_URL}/performers?location_id=11111111-1111-1111-1111-111111111111&page=1&page_size=10"
```

### 4.4 `GET /v1/events`

```bash
curl -s "${BASE_URL}/events?location_id=11111111-1111-1111-1111-111111111111&page=1&page_size=10"
```

Optional filtered browse:

```bash
curl -s "${BASE_URL}/events?location_id=11111111-1111-1111-1111-111111111111&venue_id=31111111-1111-1111-1111-111111111111&performer_id=41111111-1111-1111-1111-111111111111&page=1&page_size=10"
```

### 4.5 `GET /v1/event_detail/{eventId}`

```bash
curl -s "${BASE_URL}/event_detail/51111111-1111-1111-1111-111111111111"
```

### 4.6 `POST /v1/queue/enter`

```bash
curl -s -X POST "${BASE_URL}/queue/enter" \
  -H "Authorization: Bearer ${JWT}" \
  -H "Content-Type: application/json" \
  -d '{
    "eventId": "51111111-1111-1111-1111-111111111111",
    "categoryId": "61111111-1111-1111-1111-111111111111"
  }'
```

### 4.7 `POST /v1/queue/poll`

```bash
curl -s -X POST "${BASE_URL}/queue/poll" \
  -H "Authorization: Bearer ${JWT}" \
  -H "Content-Type: application/json" \
  -d '{
    "eventId": "51111111-1111-1111-1111-111111111111",
    "categoryId": "61111111-1111-1111-1111-111111111111",
    "sessionId": "'"${SESSION_ID}"'"
  }'
```

### 4.8 `POST /v1/queue/release`

```bash
curl -s -X POST "${BASE_URL}/queue/release" \
  -H "Authorization: Bearer ${JWT}" \
  -H "Content-Type: application/json" \
  -d '{
    "eventId": "51111111-1111-1111-1111-111111111111",
    "categoryId": "61111111-1111-1111-1111-111111111111",
    "sessionId": "'"${SESSION_ID}"'"
  }'
```

### 4.9 `GET /v1/event/{eventId}/seats`

```bash
curl -s "${BASE_URL}/event/51111111-1111-1111-1111-111111111111/seats?category_id=61111111-1111-1111-1111-111111111111&limit=20" \
  -H "Authorization: Bearer ${JWT}" \
  -H "x-booking-token: ${BOOKING_TOKEN}"
```

### 4.10 `POST /v1/reserveticket`

```bash
curl -s -X POST "${BASE_URL}/reserveticket" \
  -H "Authorization: Bearer ${JWT}" \
  -H "x-booking-token: ${BOOKING_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "eventId": "51111111-1111-1111-1111-111111111111",
    "categoryId": "61111111-1111-1111-1111-111111111111",
    "seats": [
      { "seatId": "'"${SEAT_ID_1}"'" },
      { "seatId": "'"${SEAT_ID_2}"'" }
    ],
    "idempotencyKey": "idem-pune-vip-001"
  }'
```

### 4.11 `POST /v1/payment`

Use the amount/currency returned by `reserveticket`.

```bash
curl -s -X POST "${BASE_URL}/payment" \
  -H "Authorization: Bearer ${JWT}" \
  -H "Content-Type: application/json" \
  -d '{
    "reservationId": "'"${RESERVATION_ID}"'",
    "amount": 6000,
    "currency": "INR",
    "returnUrl": "https://example.com/payment/return"
  }'
```

### 4.12 `POST /v1/booking`

```bash
curl -s -X POST "${BASE_URL}/booking" \
  -H "Authorization: Bearer ${JWT}" \
  -H "x-booking-token: ${BOOKING_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "reservationId": "'"${RESERVATION_ID}"'",
    "paymentId": "'"${PAYMENT_ID}"'"
  }'
```

---

## 5) Runtime values you cannot pre-seed in DB

These are produced during the live API flow and should be captured from previous API responses:

- `SESSION_ID` → from `POST /queue/enter`
- `BOOKING_TOKEN` → from `POST /queue/enter` or `POST /queue/poll` when the session becomes allowed
- `RESERVATION_ID` → from `POST /reserveticket`
- `PAYMENT_ID` → from `POST /payment`

---

## 6) Quick verification queries

```sql
SELECT id, name FROM public.locations ORDER BY name;
SELECT id, name, location_id FROM public.venues ORDER BY name;
SELECT id, name FROM public.performers ORDER BY name;
SELECT id, name, venue_id, event_date, status FROM public.events ORDER BY event_date;
SELECT id, event_id, name, price, currency FROM public.event_categories ORDER BY event_id, name;
SELECT event_id, category_id, count(*) AS seats_per_category
FROM public.seats
GROUP BY event_id, category_id
ORDER BY event_id, category_id;
```
