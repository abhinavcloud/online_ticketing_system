\set ON_ERROR_STOP on
\pset pager off

\echo '================================================'\echo '============================================================'
\echo 'DB        : ' :DBNAME
\echo 'User      : ' :USER
\echo 'Host      : ' :HOST
\echo 'Seed flag : ' :{?seed}
\echo '============================================================'

SET client_min_messages TO WARNING;
SET statement_timeout TO '10min';

-- ----------------------------
-- 1) Extensions
-- ----------------------------
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
COMMIT;

\echo 'Extensions ensured (pgcrypto).'

-- ----------------------------
-- 2) Enums (idempotent)
-- ----------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'event_status') THEN
    CREATE TYPE event_status AS ENUM ('DRAFT','ON_SALE','SOLD_OUT','CANCELLED');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'seat_status') THEN
    CREATE TYPE seat_status AS ENUM ('AVAILABLE','BOOKED');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'reservation_status') THEN
    CREATE TYPE reservation_status AS ENUM ('HOLD','CONFIRMED','CANCELLED','EXPIRED','FAILED');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'cancel_reason') THEN
    CREATE TYPE cancel_reason AS ENUM ('PAYMENT_FAILED','USER_CANCELLED','TIMEOUT','SYSTEM_ABORT');
  END IF;
END $$;

\echo 'Enums ensured.'

-- ----------------------------
-- 3) Location/Venue/Performer tables (for Browse APIs)
-- ----------------------------
BEGIN;

CREATE TABLE IF NOT EXISTS public.locations (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name         TEXT NOT NULL UNIQUE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.venues (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  location_id  UUID NOT NULL REFERENCES public.locations(id),
  name         TEXT NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(location_id, name)
);

CREATE TABLE IF NOT EXISTS public.performers (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name         TEXT NOT NULL UNIQUE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMIT;

\echo 'Core browse tables ensured (locations, venues, performers).'

-- ----------------------------
-- 4) Events table (extend your existing public.events)
--     Your current: id, name, event_date
--     Add: description, status, venue_id, event_type
-- ----------------------------
BEGIN;

CREATE TABLE IF NOT EXISTS public.events (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  event_date TIMESTAMP NOT NULL
);

ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS description TEXT;

ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS status event_status NOT NULL DEFAULT 'ON_SALE';

ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS venue_id UUID REFERENCES public.venues(id);

-- optional field to support "category": "Concert" in list events response
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS event_type TEXT;

ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();

ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

COMMIT;

\echo 'Events table ensured + extended.'

-- ----------------------------
-- 5) Event ↔ Performers (many-to-many)
-- ----------------------------
BEGIN;

CREATE TABLE IF NOT EXISTS public.event_performers (
  event_id     UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  performer_id UUID NOT NULL REFERENCES public.performers(id),
  PRIMARY KEY (event_id, performer_id)
);

COMMIT;

\echo 'Event performers ensured.'

-- ----------------------------
-- 6) Event Categories (for /v1/event/{eventId} ticketCategories)
-- ----------------------------
BEGIN;

CREATE TABLE IF NOT EXISTS public.event_categories (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id    UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,              -- VIP, General
  price       BIGINT NOT NULL CHECK(price >= 0),
  currency    TEXT NOT NULL DEFAULT 'INR',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(event_id, name)
);

COMMIT;

\echo 'Event categories ensured.'

-- ----------------------------
-- 7) Seats table (extend your existing public.seats)
--     Your current: id, event_id, seat_number
--     Add: category_id, status, row, number, booked_at, updated_at
-- ----------------------------
BEGIN;

CREATE TABLE IF NOT EXISTS public.seats (
  id UUID PRIMARY KEY,
  event_id UUID REFERENCES public.events(id),
  seat_number TEXT NOT NULL,
  UNIQUE(event_id, seat_number)
);

ALTER TABLE public.seats
  ADD COLUMN IF NOT EXISTS category_id UUID REFERENCES public.event_categories(id);

ALTER TABLE public.seats
  ADD COLUMN IF NOT EXISTS status seat_status NOT NULL DEFAULT 'AVAILABLE';

ALTER TABLE public.seats
  ADD COLUMN IF NOT EXISTS seat_row TEXT;

ALTER TABLE public.seats
  ADD COLUMN IF NOT EXISTS seat_no INT;

ALTER TABLE public.seats
  ADD COLUMN IF NOT EXISTS booked_at TIMESTAMPTZ;

ALTER TABLE public.seats
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();

ALTER TABLE public.seats
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

COMMIT;

\echo 'Seats table ensured + extended.'

-- ----------------------------
-- 8) Reservations table (extend your existing public.reservations)
--     Your current supports single seat_id.
--     Your API requires MULTI-seat reservations.
--     We keep your table, add fields, and store seat list in reservation_seats.
-- ----------------------------
BEGIN;

CREATE TABLE IF NOT EXISTS public.reservations (
  id UUID PRIMARY KEY,
  seat_id UUID NOT NULL REFERENCES public.seats(id),
  user_id TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  event_id UUID NOT NULL,
  expires_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- allow legacy seat_id to be nullable (multi-seat will use reservation_seats)
ALTER TABLE public.reservations
  ALTER COLUMN seat_id DROP NOT NULL;

-- status as enum for correctness
ALTER TABLE public.reservations
  ALTER COLUMN status TYPE reservation_status
  USING status::reservation_status;

ALTER TABLE public.reservations
  ADD COLUMN IF NOT EXISTS category_id UUID REFERENCES public.event_categories(id);

ALTER TABLE public.reservations
  ADD COLUMN IF NOT EXISTS idempotency_key TEXT;

ALTER TABLE public.reservations
  ADD COLUMN IF NOT EXISTS payment_ref TEXT;

ALTER TABLE public.reservations
  ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ;

ALTER TABLE public.reservations
  ADD COLUMN IF NOT EXISTS cancel_reason cancel_reason;

ALTER TABLE public.reservations
  ADD COLUMN IF NOT EXISTS failure_reason TEXT;

-- helpful uniqueness for retries (your cancel API has idempotencyKey)
CREATE UNIQUE INDEX IF NOT EXISTS uq_reservation_idempotency
  ON public.reservations(user_id, event_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

COMMIT;

\echo 'Reservations table ensured + extended.'

-- ----------------------------
-- 9) Reservation Seats (multi-seat mapping)
-- ----------------------------
BEGIN;

CREATE TABLE IF NOT EXISTS public.reservation_seats (
  reservation_id UUID NOT NULL REFERENCES public.reservations(id) ON DELETE CASCADE,
  event_id       UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  seat_id        UUID NOT NULL REFERENCES public.seats(id),
  status         reservation_status NOT NULL DEFAULT 'HOLD',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (reservation_id, seat_id)
);

-- correctness: one active HOLD/CONFIRMED per (event_id, seat_id)
CREATE UNIQUE INDEX IF NOT EXISTS uq_active_hold_per_event_seat
  ON public.reservation_seats(event_id, seat_id)
  WHERE status IN ('HOLD','CONFIRMED');

COMMIT;

\echo 'Reservation seats ensured + correctness index created.'

-- ----------------------------
-- 10) Tickets table (final booking record)
-- ----------------------------
BEGIN;

CREATE TABLE IF NOT EXISTS public.tickets (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id     UUID NOT NULL DEFAULT gen_random_uuid(), -- group seats for same booking
  reservation_id UUID NOT NULL REFERENCES public.reservations(id),
  event_id       UUID NOT NULL REFERENCES public.events(id),
  category_id    UUID NOT NULL REFERENCES public.event_categories(id),
  seat_id        UUID NOT NULL REFERENCES public.seats(id),
  user_id        TEXT NOT NULL,
  amount_paid    BIGINT NOT NULL CHECK(amount_paid >= 0),
  currency       TEXT NOT NULL DEFAULT 'INR',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(event_id, seat_id)
);

COMMIT;

\echo 'Tickets table ensured.'

-- ----------------------------
-- 11) Indexes for your API queries
-- ----------------------------
BEGIN;

-- Browse
CREATE INDEX IF NOT EXISTS idx_venues_location
  ON public.venues(location_id);

CREATE INDEX IF NOT EXISTS idx_events_venue_date
  ON public.events(venue_id, event_date);

CREATE INDEX IF NOT EXISTS idx_event_performers_perf
  ON public.event_performers(performer_id, event_id);

CREATE INDEX IF NOT EXISTS idx_event_categories_event
  ON public.event_categories(event_id);

-- Seats API
CREATE INDEX IF NOT EXISTS idx_seats_event_category_status
  ON public.seats(event_id, category_id, status);

CREATE INDEX IF NOT EXISTS idx_seats_event_status
  ON public.seats(event_id, status);

-- Reservation lookup
CREATE INDEX IF NOT EXISTS idx_reservations_user_event_status
  ON public.reservations(user_id, event_id, status);

CREATE INDEX IF NOT EXISTS idx_reservations_expires_hold
  ON public.reservations(expires_at)
  WHERE status = 'HOLD';

COMMIT;

\echo 'Indexes ensured.'

-- ----------------------------
-- 12) Optional seed data (run with -v seed=1)
--     Produces:
--       1 location, 1 venue, 1 performer, 1 event
--       2 categories (VIP, General)
--       N seats for the event assigned to categories
-- ----------------------------
\if :{?location_name}
\else
  \set location_name 'Pune'
\endif

\if :{?venue_name}
\else
  \set venue_name 'Big Arena'
\endif

\if :{?performer_name}
\else
  \set performer_name 'Demo Performer'
\endif

\if :{?event_name}
\else
  \set event_name 'Demo Event'
\endif

\if :{?seat_count}
\else
  \set seat_count 200
\endif

\if :{?vip_pct}
\else
  \set vip_pct 20
\endif

\if :{?seed}
  \echo 'Seeding enabled...'

  BEGIN;

  -- location
  INSERT INTO public.locations(name)
  SELECT :'location_name'
  WHERE NOT EXISTS (SELECT 1 FROM public.locations WHERE name = :'location_name');

  -- venue
  INSERT INTO public.venues(location_id, name)
  SELECT l.id, :'venue_name'
  FROM public.locations l
  WHERE l.name = :'location_name'
    AND NOT EXISTS (
      SELECT 1 FROM public.venues v WHERE v.location_id = l.id AND v.name = :'venue_name'
    );

  -- performer
  INSERT INTO public.performers(name)
  SELECT :'performer_name'
  WHERE NOT EXISTS (SELECT 1 FROM public.performers WHERE name = :'performer_name');

  -- event
  INSERT INTO public.events(id, name, event_date, description, status, venue_id, event_type)
  SELECT
    gen_random_uuid(),
    :'event_name',
    now() + interval '7 days',
    'Seeded event',
    'ON_SALE',
    v.id,
    'Concert'
  FROM public.venues v
  JOIN public.locations l ON l.id = v.location_id
  WHERE l.name = :'location_name' AND v.name = :'venue_name'
    AND NOT EXISTS (
      SELECT 1 FROM public.events e WHERE e.name = :'event_name' AND e.venue_id = v.id
    );

  -- attach performer to event
  INSERT INTO public.event_performers(event_id, performer_id)
  SELECT e.id, p.id
  FROM public.events e
  JOIN public.performers p ON p.name = :'performer_name'
  WHERE e.name = :'event_name'
  ON CONFLICT DO NOTHING;

  -- categories
  INSERT INTO public.event_categories(event_id, name, price, currency)
  SELECT e.id, 'VIP', 3000, 'INR'
  FROM public.events e
  WHERE e.name = :'event_name'
  ON CONFLICT DO NOTHING;

  INSERT INTO public.event_categories(event_id, name, price, currency)
  SELECT e.id, 'General', 500, 'INR'
  FROM public.events e
  WHERE e.name = :'event_name'
  ON CONFLICT DO NOTHING;

  -- seats (seat_number is your API seatId value)
  WITH e AS (
    SELECT id AS event_id
    FROM public.events
    WHERE name = :'event_name'
    ORDER BY event_date DESC
    LIMIT 1
  ),
  vip AS (
    SELECT id AS vip_cat_id FROM public.event_categories c JOIN e ON c.event_id = e.event_id WHERE c.name='VIP' LIMIT 1
  ),
  gen AS (
    SELECT id AS gen_cat_id FROM public.event_categories c JOIN e ON c.event_id = e.event_id WHERE c.name='General' LIMIT 1
  ),
  s AS (
    SELECT generate_series(1, :seat_count::int) AS n
  )
  INSERT INTO public.seats(id, event_id, seat_number, category_id, status, seat_row, seat_no)
  SELECT
    gen_random_uuid(),
    e.event_id,
    'A-' || lpad(s.n::text, 4, '0'),
    CASE WHEN (s.n * 100 / :seat_count::int) <= :vip_pct::int THEN vip.vip_cat_id ELSE gen.gen_cat_id END,
    'AVAILABLE',
    'A',
    s.n
  FROM e, vip, gen, s
  ON CONFLICT (event_id, seat_number) DO NOTHING;

  COMMIT;

  \echo 'Seeding done.'
\else
  \echo 'Seeding skipped. (Run with -v seed=1 to seed).'
\endif

-- ----------------------------
-- 13) Summary
-- ----------------------------
\echo '============================================================'
\echo 'Bootstrap summary (counts):'
SELECT 'locations' AS table, count(*) FROM public.locations
UNION ALL SELECT 'venues', count(*) FROM public.venues
UNION ALL SELECT 'performers', count(*) FROM public.performers
UNION ALL SELECT 'events', count(*) FROM public.events
UNION ALL SELECT 'event_categories', count(*) FROM public.event_categories
UNION ALL SELECT 'seats', count(*) FROM public.seats
UNION ALL SELECT 'reservations', count(*) FROM public.reservations
UNION ALL SELECT 'reservation_seats', count(*) FROM public.reservation_seats
UNION ALL SELECT 'tickets', count(*) FROM public.tickets;

\echo '============================================================'
\echo 'Ticketing bootstrap completed successfully.'
\echo '============================================================'
