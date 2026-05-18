\set ON_ERROR_STOP on
\pset pager off

\echo '============================================================'
\echo 'Ticketing bootstrap starting...'
\echo 'DB        : ' :DBNAME
\echo 'User      : ' :USER
\echo 'Host      : ' :HOST
\echo 'Seed flag : ' :{?seed}
\echo '============================================================'

-- ----------------------------
-- 0) Safe defaults
-- ----------------------------
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
-- 2) Types (enums) - idempotent
-- ----------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'event_status') THEN
    CREATE TYPE event_status AS ENUM ('DRAFT', 'ON_SALE', 'SOLD_OUT', 'CANCELLED');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'seat_status') THEN
    CREATE TYPE seat_status AS ENUM ('AVAILABLE', 'BOOKED');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'reservation_status') THEN
    CREATE TYPE reservation_status AS ENUM ('HOLD', 'CONFIRMED', 'CANCELLED', 'EXPIRED', 'FAILED');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'cancel_reason') THEN
    CREATE TYPE cancel_reason AS ENUM ('PAYMENT_FAILED', 'USER_CANCELLED', 'TIMEOUT', 'SYSTEM_ABORT');
  END IF;
END $$;

\echo 'Types ensured (event_status, seat_status, reservation_status, cancel_reason).'

-- ----------------------------
-- 3) Core browse schema
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
  UNIQUE (location_id, name)
);

CREATE TABLE IF NOT EXISTS public.performers (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name         TEXT NOT NULL UNIQUE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Events live at a venue (which is in a location)
CREATE TABLE IF NOT EXISTS public.events (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL,
  description   TEXT,
  venue_id      UUID NOT NULL REFERENCES public.venues(id),
  event_date    TIMESTAMPTZ NOT NULL,
  status        event_status NOT NULL DEFAULT 'DRAFT',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Many-to-many event ↔ performers
CREATE TABLE IF NOT EXISTS public.event_performers (
  event_id      UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  performer_id  UUID NOT NULL REFERENCES public.performers(id),
  PRIMARY KEY (event_id, performer_id)
);

-- Ticket categories are per event (price/currency)
CREATE TABLE IF NOT EXISTS public.event_categories (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id      UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,                 -- VIP / General
  price         BIGINT NOT NULL CHECK (price >= 0),
  currency      TEXT NOT NULL DEFAULT 'INR',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (event_id, name)
);

COMMIT;

\echo 'Core browse schema ensured (locations, venues, performers, events, event_performers, event_categories).'

-- ----------------------------
-- 4) Seats schema (per event)
-- ----------------------------
BEGIN;

CREATE TABLE IF NOT EXISTS public.seats (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id       UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  category_id    UUID NOT NULL REFERENCES public.event_categories(id),
  seat_label     TEXT NOT NULL,               -- A-01-01 or A-1 etc
  seat_row       TEXT,
  seat_number    INT,
  status         seat_status NOT NULL DEFAULT 'AVAILABLE',
  booked_at      TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(event_id, seat_label)
);

COMMIT;

\echo 'Seats schema ensured (seats).'

-- ----------------------------
-- 5) Reservations + Reservation Seats (multi-seat HOLD)
-- ----------------------------
BEGIN;

CREATE TABLE IF NOT EXISTS public.reservations (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           TEXT NOT NULL,       -- from JWT sub
  event_id          UUID NOT NULL REFERENCES public.events(id),
  category_id       UUID NOT NULL REFERENCES public.event_categories(id),
  status            reservation_status NOT NULL DEFAULT 'HOLD',
  idempotency_key   TEXT,                -- optional but recommended
  expires_at        TIMESTAMPTZ,          -- align to Redis TTL
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  payment_ref       TEXT,
  failure_reason    TEXT,
  cancel_reason     cancel_reason,
  UNIQUE (user_id, event_id, idempotency_key)
);

-- Stores each seat held/confirmed under a reservation
CREATE TABLE IF NOT EXISTS public.reservation_seats (
  reservation_id  UUID NOT NULL REFERENCES public.reservations(id) ON DELETE CASCADE,
  seat_id         UUID NOT NULL REFERENCES public.seats(id),
  status          reservation_status NOT NULL DEFAULT 'HOLD',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (reservation_id, seat_id)
);

COMMIT;

\echo 'Reservation schema ensured (reservations, reservation_seats).'

-- ----------------------------
-- 6) Correctness constraints for "one active HOLD/CONFIRMED per seat"
--     Enforced at reservation_seats level (simple + works with multi-seat)
-- ----------------------------
BEGIN;

-- Critical correctness: one active hold/confirmed record per seat across all reservations
CREATE UNIQUE INDEX IF NOT EXISTS uq_active_reservation_per_seat
  ON public.reservation_seats(seat_id)
  WHERE status IN ('HOLD', 'CONFIRMED');

COMMIT;

\echo 'Correctness ensured (uq_active_reservation_per_seat).'

-- ----------------------------
-- 7) Tickets table (final booking record)
-- ----------------------------
BEGIN;

CREATE TABLE IF NOT EXISTS public.tickets (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id     UUID NOT NULL DEFAULT gen_random_uuid(), -- group tickets under booking
  reservation_id UUID NOT NULL REFERENCES public.reservations(id),
  event_id       UUID NOT NULL REFERENCES public.events(id),
  category_id    UUID NOT NULL REFERENCES public.event_categories(id),
  seat_id        UUID NOT NULL REFERENCES public.seats(id),
  user_id        TEXT NOT NULL,
  amount_paid    BIGINT NOT NULL CHECK (amount_paid >= 0),
  currency       TEXT NOT NULL DEFAULT 'INR',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(event_id, seat_id)  -- final safety against double booking
);

COMMIT;

\echo 'Tickets schema ensured (tickets).'

-- ----------------------------
-- 8) Indexes for API performance
-- ----------------------------
BEGIN;

-- Browse filters
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

-- Reservation queries
CREATE INDEX IF NOT EXISTS idx_reservations_user_event_status
  ON public.reservations(user_id, event_id, status);

CREATE INDEX IF NOT EXISTS idx_reservations_expires
  ON public.reservations(expires_at)
  WHERE status = 'HOLD';

COMMIT;

\echo 'Indexes ensured.'

-- ----------------------------
-- 9) Optional seed (run with -v seed=1)
--     Parameters:
--       -v location_name='Pune'
--       -v venue_name='Big Arena'
--       -v performer_name='Demo Performer'
--       -v event_name='Demo Event'
--       -v seat_count=1000
--       -v vip_pct=20
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

  -- Location
  INSERT INTO public.locations(name)
  SELECT :'location_name'
  WHERE NOT EXISTS (SELECT 1 FROM public.locations WHERE name = :'location_name');

  -- Venue
  INSERT INTO public.venues(location_id, name)
  SELECT l.id, :'venue_name'
  FROM public.locations l
  WHERE l.name = :'location_name'
    AND NOT EXISTS (
      SELECT 1 FROM public.venues v
      WHERE v.location_id = l.id AND v.name = :'venue_name'
    );

  -- Performer
  INSERT INTO public.performers(name)
  SELECT :'performer_name'
  WHERE NOT EXISTS (SELECT 1 FROM public.performers WHERE name = :'performer_name');

  -- Event
  INSERT INTO public.events(name, description, venue_id, event_date, status)
  SELECT
    :'event_name',
    'Seeded event',
    v.id,
    now() + interval '7 days',
    'ON_SALE'
  FROM public.venues v
  JOIN public.locations l ON l.id = v.location_id
  WHERE l.name = :'location_name' AND v.name = :'venue_name'
    AND NOT EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.name = :'event_name' AND e.venue_id = v.id
    );

  -- Attach performer to event
  INSERT INTO public.event_performers(event_id, performer_id)
  SELECT e.id, p.id
  FROM public.events e
  JOIN public.performers p ON p.name = :'performer_name'
  WHERE e.name = :'event_name'
  ON CONFLICT DO NOTHING;

  -- Categories
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

  -- Seats generation
  -- VIP percent based split; seat_label = A-<num>
  WITH e AS (
    SELECT id AS event_id FROM public.events WHERE name = :'event_name' ORDER BY event_date DESC LIMIT 1
  ),
  vip AS (
    SELECT id AS vip_cat_id FROM public.event_categories c
    JOIN e ON c.event_id = e.event_id
    WHERE c.name = 'VIP' LIMIT 1
  ),
  gen AS (
    SELECT id AS gen_cat_id FROM public.event_categories c
    JOIN e ON c.event_id = e.event_id
    WHERE c.name = 'General' LIMIT 1
  ),
  s AS (
    SELECT generate_series(1, :seat_count::int) AS n
  )
  INSERT INTO public.seats(event_id, category_id, seat_label, seat_row, seat_number, status)
  SELECT
    e.event_id,
    CASE WHEN (s.n * 100 / :seat_count::int) <= :vip_pct::int THEN vip.vip_cat_id ELSE gen.gen_cat_id END,
    'A-' || lpad(s.n::text, 4, '0'),
    'A',
    s.n,
    'AVAILABLE'
  FROM e, vip, gen, s
  ON CONFLICT (event_id, seat_label) DO NOTHING;

  COMMIT;

  \echo 'Seeding done.'
\else
  \echo 'Seeding skipped. (Run with -v seed=1 to seed).'
\endif

-- ----------------------------
-- 10) Quick verification
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