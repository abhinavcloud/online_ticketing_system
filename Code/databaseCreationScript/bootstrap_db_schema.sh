#!/bin/bash
set -euo pipefail

echo "=================================================="
echo " Ticketing DB Bootstrap (Single Script)"
echo "=================================================="

# ---------------------------
# 0. Validate connection
# ---------------------------
if [ -z "${DB_CONN:-}" ]; then
  echo "❌ ERROR: DB_CONN not set"
  echo 'export DB_CONN="host=... port=5432 dbname=onlineticketingsystem user=... sslmode=require"'
  exit 1
fi

# ---------------------------
# 1. Defaults (override if needed)
# ---------------------------
SEED=${SEED:-1}
LOCATION_NAME=${LOCATION_NAME:-Pune}
VENUE_NAME=${VENUE_NAME:-Big Arena}
VENUE_ADDRESS=${VENUE_ADDRESS:-"Demo Venue Address"}
PERFORMER_NAME=${PERFORMER_NAME:-Demo Performer}
EVENT_NAME=${EVENT_NAME:-Demo Event}
EVENT_TYPE=${EVENT_TYPE:-Concert}
EVENT_TIME=${EVENT_TIME:-19:30:00}
SEAT_COUNT=${SEAT_COUNT:-200}
VIP_PCT=${VIP_PCT:-20}
CURRENCY=${CURRENCY:-INR}

echo "Using config:"
echo "Seed=$SEED | Location=$LOCATION_NAME | Venue=$VENUE_NAME | Event=$EVENT_NAME"

echo "=================================================="

# ---------------------------
# 2. Execute ALL SQL inline
# ---------------------------

psql "$DB_CONN" -v ON_ERROR_STOP=1 <<SQL

-- =====================================
-- 1) CREATE APP USER + IAM
-- =====================================
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user') THEN
    CREATE USER app_user LOGIN;
  END IF;
END \$\$;

GRANT rds_iam TO app_user;

GRANT CONNECT ON DATABASE onlineticketingsystem TO app_user;
GRANT USAGE ON SCHEMA public TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO app_user;

-- =====================================
-- 2) EXTENSIONS + TYPES
-- =====================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO \$\$
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
END \$\$;

-- =====================================
-- 3) CORE TABLES
-- =====================================

CREATE TABLE IF NOT EXISTS public.locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT UNIQUE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.venues (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  location_id UUID REFERENCES public.locations(id),
  name TEXT NOT NULL,
  address TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(location_id, name)
);

CREATE TABLE IF NOT EXISTS public.performers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT UNIQUE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  venue_id UUID REFERENCES public.venues(id),
  event_date TIMESTAMPTZ,
  event_time TIME,
  event_type TEXT,
  status event_status NOT NULL DEFAULT 'DRAFT',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Make event insert idempotent across reruns
DO \$\$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'uq_events_name_venue_date'
  ) THEN
    ALTER TABLE public.events
      ADD CONSTRAINT uq_events_name_venue_date UNIQUE (name, venue_id, event_date);
  END IF;
END \$\$;

-- Event-performer mapping (needed by Browse Service /performers + /events)
CREATE TABLE IF NOT EXISTS public.event_performers (
  event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  performer_id UUID NOT NULL REFERENCES public.performers(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (event_id, performer_id)
);

-- =====================================
-- 4) CATEGORIES + SEATS
-- =====================================

CREATE TABLE IF NOT EXISTS public.event_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  price BIGINT NOT NULL,
  currency TEXT NOT NULL DEFAULT '$CURRENCY',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO \$\$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'uq_event_category_name'
  ) THEN
    ALTER TABLE public.event_categories
      ADD CONSTRAINT uq_event_category_name UNIQUE (event_id, name);
  END IF;
END \$\$;

CREATE TABLE IF NOT EXISTS public.seats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  category_id UUID NOT NULL REFERENCES public.event_categories(id) ON DELETE CASCADE,
  seat_label TEXT NOT NULL,
  status seat_status NOT NULL DEFAULT 'AVAILABLE',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  booked_at TIMESTAMPTZ,
  UNIQUE(event_id, seat_label)
);

CREATE INDEX IF NOT EXISTS idx_seats_event_category_status
  ON public.seats(event_id, category_id, status);

-- =====================================
-- 5) RESERVATIONS + RESERVATION_SEATS
-- =====================================
-- NOTE:
-- Your finalized services use cache-only seat locks.
-- DB does NOT drive LOCKED state.
-- These tables are kept for:
--   - FAILED reservation audit
--   - future extensibility
--   - optional confirmation/audit evolution

CREATE TABLE IF NOT EXISTS public.reservations (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          TEXT NOT NULL,   -- Cognito sub
  event_id         UUID NOT NULL REFERENCES public.events(id),
  category_id      UUID NOT NULL REFERENCES public.event_categories(id),
  status           reservation_status NOT NULL DEFAULT 'HOLD',
  idempotency_key  TEXT,
  expires_at       TIMESTAMPTZ,
  failure_reason   TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, event_id, idempotency_key)
);

CREATE TABLE IF NOT EXISTS public.reservation_seats (
  reservation_id UUID NOT NULL REFERENCES public.reservations(id) ON DELETE CASCADE,
  event_id       UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  seat_id        UUID NOT NULL REFERENCES public.seats(id),
  status         reservation_status NOT NULL DEFAULT 'HOLD',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (reservation_id, seat_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_active_reservation_per_seat
  ON public.reservation_seats(seat_id)
  WHERE status IN ('HOLD', 'CONFIRMED');

-- =====================================
-- 6) TICKETS
-- =====================================
-- Booking Confirmation service inserts into this table

CREATE TABLE IF NOT EXISTS public.tickets (
  id UUID PRIMARY KEY,
  user_id TEXT NOT NULL,
  reservation_id UUID NOT NULL,
  payment_id UUID NOT NULL,
  event_id UUID NOT NULL REFERENCES public.events(id),
  category_id UUID NOT NULL REFERENCES public.event_categories(id),
  venue_id UUID NOT NULL REFERENCES public.venues(id),
  seat_label TEXT NOT NULL,
  unit_price BIGINT NOT NULL,
  total_amount BIGINT NOT NULL,
  currency TEXT NOT NULL,
  event_name TEXT NOT NULL,
  event_date TIMESTAMPTZ,
  event_time TIME,
  venue_name TEXT,
  venue_address TEXT,
  category_name TEXT,
  status TEXT NOT NULL DEFAULT 'CONFIRMED',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tickets_reservation_id
  ON public.tickets(reservation_id);

CREATE INDEX IF NOT EXISTS idx_tickets_event_id
  ON public.tickets(event_id);

CREATE INDEX IF NOT EXISTS idx_tickets_user_id
  ON public.tickets(user_id);

-- =====================================
-- 7) OPTIONAL SEED
-- =====================================
DO \$\$
DECLARE
  v_location_id UUID;
  v_venue_id UUID;
  v_event_id UUID;
  v_performer_id UUID;
  v_vip UUID;
  v_gen UUID;
  i INT;
BEGIN
IF $SEED = 1 THEN

  -- Location
  INSERT INTO public.locations(name)
  VALUES ('$LOCATION_NAME')
  ON CONFLICT (name) DO NOTHING;

  SELECT id INTO v_location_id
  FROM public.locations
  WHERE name = '$LOCATION_NAME';

  -- Venue
  INSERT INTO public.venues(location_id, name, address)
  VALUES (v_location_id, '$VENUE_NAME', '$VENUE_ADDRESS')
  ON CONFLICT (location_id, name) DO NOTHING;

  SELECT id INTO v_venue_id
  FROM public.venues
  WHERE location_id = v_location_id
    AND name = '$VENUE_NAME';

  -- Performer
  INSERT INTO public.performers(name)
  VALUES ('$PERFORMER_NAME')
  ON CONFLICT (name) DO NOTHING;

  SELECT id INTO v_performer_id
  FROM public.performers
  WHERE name = '$PERFORMER_NAME';

  -- Event
  INSERT INTO public.events(name, venue_id, event_date, event_time, event_type, status)
  VALUES (
    '$EVENT_NAME',
    v_venue_id,
    (now() + interval '7 day'),
    '$EVENT_TIME',
    '$EVENT_TYPE',
    'ON_SALE'
  )
  ON CONFLICT (name, venue_id, event_date) DO NOTHING;

  SELECT id INTO v_event_id
  FROM public.events
  WHERE name = '$EVENT_NAME'
    AND venue_id = v_venue_id
  ORDER BY created_at DESC
  LIMIT 1;

  -- Event-performer link
  INSERT INTO public.event_performers(event_id, performer_id)
  VALUES (v_event_id, v_performer_id)
  ON CONFLICT DO NOTHING;

  -- Categories
  INSERT INTO public.event_categories(event_id, name, price, currency)
  VALUES (v_event_id, 'VIP', 3000, '$CURRENCY')
  ON CONFLICT (event_id, name) DO NOTHING;

  INSERT INTO public.event_categories(event_id, name, price, currency)
  VALUES (v_event_id, 'General', 500, '$CURRENCY')
  ON CONFLICT (event_id, name) DO NOTHING;

  SELECT id INTO v_vip
  FROM public.event_categories
  WHERE event_id = v_event_id
    AND name = 'VIP';

  SELECT id INTO v_gen
  FROM public.event_categories
  WHERE event_id = v_event_id
    AND name = 'General';

  -- Seats
  FOR i IN 1..$SEAT_COUNT LOOP
    INSERT INTO public.seats(event_id, category_id, seat_label)
    VALUES (
      v_event_id,
      CASE
        WHEN (i * 100 / $SEAT_COUNT) <= $VIP_PCT THEN v_vip
        ELSE v_gen
      END,
      'A-' || LPAD(i::text, 4, '0')
    )
    ON CONFLICT (event_id, seat_label) DO NOTHING;
  END LOOP;

END IF;
END \$\$;

-- =====================================
-- 8) VERIFICATION
-- =====================================
SELECT 'tables_created' as status;

SQL

echo "=================================================="
echo "✅ DB Bootstrap DONE (single script)"
echo "=================================================="