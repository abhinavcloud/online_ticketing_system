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
-- 0) Safety + required settings
-- ----------------------------
SET client_min_messages TO WARNING;
SET statement_timeout TO '5min';

-- ----------------------------
-- 1) Schema: extensions
-- ----------------------------
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

COMMIT;

\echo 'Extensions ensured (pgcrypto).'

-- ----------------------------
-- 2) Schema: tables
-- ----------------------------
BEGIN;

CREATE TABLE IF NOT EXISTS public.events (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  event_date TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS public.seats (
  id UUID PRIMARY KEY,
  event_id UUID REFERENCES public.events(id),
  seat_number TEXT NOT NULL,
  UNIQUE(event_id, seat_number)
);

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

COMMIT;

\echo 'Tables ensured (events, seats, reservations).'

-- ----------------------------
-- 3) Schema: constraints (idempotent via DO blocks)
-- ----------------------------
BEGIN;

-- Ensure seat_id is NOT NULL (idempotent)
ALTER TABLE public.reservations
  ALTER COLUMN seat_id SET NOT NULL;

-- Add status CHECK constraint only if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'reservations_status_chk'
      AND conrelid = 'public.reservations'::regclass
  ) THEN
    ALTER TABLE public.reservations
      ADD CONSTRAINT reservations_status_chk
      CHECK (status IN ('HOLD', 'CONFIRMED', 'CANCELLED', 'EXPIRED', 'FAILED'));
  END IF;
END $$;

COMMIT;

\echo 'Constraints ensured (seat_id NOT NULL, status check).'

-- ----------------------------
-- 4) Schema: indexes (idempotent)
-- ----------------------------
BEGIN;

CREATE INDEX IF NOT EXISTS idx_seats_event
  ON public.seats(event_id);

CREATE INDEX IF NOT EXISTS idx_reservations_seat
  ON public.reservations(seat_id);

CREATE INDEX IF NOT EXISTS idx_reservations_status
  ON public.reservations(status);

CREATE INDEX IF NOT EXISTS idx_reservations_event_status
  ON public.reservations(event_id, status);

CREATE INDEX IF NOT EXISTS idx_reservations_expires
  ON public.reservations(expires_at)
  WHERE status = 'HOLD';

-- Critical correctness: one active reservation per seat
CREATE UNIQUE INDEX IF NOT EXISTS uq_reservations_active_seat
  ON public.reservations(seat_id)
  WHERE status IN ('HOLD', 'CONFIRMED');

COMMIT;

\echo 'Indexes ensured (including partial unique uq_reservations_active_seat).'

-- ----------------------------
-- 5) Optional seed (enabled using: -v seed=1)
--     Also supports override variables:
--       -v event_name='Seed Event'
--       -v seat_prefix='A'
--       -v seat_count=100
-- ----------------------------

-- Defaults if user did not pass variables
\if :{?event_name}
\else
  \set event_name 'Seed Event'
\endif

\if :{?seat_prefix}
\else
  \set seat_prefix 'A'
\endif

\if :{?seat_count}
\else
  \set seat_count 100
\endif

\if :{?seed}
  \echo 'Seeding enabled...'
  \echo 'Event name  : ' :event_name
  \echo 'Seat prefix : ' :seat_prefix
  \echo 'Seat count  : ' :seat_count

  BEGIN;

  -- Insert exactly one seed event by name if it doesn't exist
  INSERT INTO public.events (id, name, event_date)
  SELECT gen_random_uuid(), :'event_name', now() + interval '7 days'
  WHERE NOT EXISTS (
    SELECT 1 FROM public.events WHERE name = :'event_name'
  );

  -- Fetch the seed event id deterministically (same name)
  WITH e AS (
    SELECT id
    FROM public.events
    WHERE name = :'event_name'
    ORDER BY event_date DESC
    LIMIT 1
  )
  INSERT INTO public.seats (id, event_id, seat_number)
  SELECT
    gen_random_uuid(),
    e.id,
    (:'seat_prefix' || '-' || s.num::text)
  FROM e
  CROSS JOIN generate_series(1, :seat_count::int) AS s(num)
  ON CONFLICT (event_id, seat_number) DO NOTHING;

  COMMIT;

  \echo 'Seeding done.'
\else
  \echo 'Seeding skipped. (Run with -v seed=1 to seed).'
\endif

-- ----------------------------
-- 6) Post-run verification summary
-- ----------------------------
\echo '============================================================'
\echo 'Bootstrap summary:'
SELECT 'events' AS table, count(*) FROM public.events
UNION ALL
SELECT 'seats', count(*) FROM public.seats
UNION ALL
SELECT 'reservations', count(*) FROM public.reservations;

\echo 'Active reservations (HOLD/CONFIRMED) count:'
SELECT count(*) AS active_reservations
FROM public.reservations
WHERE status IN ('HOLD', 'CONFIRMED');

\echo '============================================================'
\echo 'Ticketing bootstrap completed successfully.'
\echo '============================================================'