#!/bin/bash
set -euo pipefail

echo "=================================================="
echo " Ticketing DB Bootstrap (Schema + Seed Data)"
echo "=================================================="

# -----------------------------------------------------------------------------
# 0. Validate connection
# -----------------------------------------------------------------------------
if [ -z "${DB_CONN:-}" ]; then
  echo "ERROR: DB_CONN not set"
  echo 'Example:'
  echo 'export DB_CONN="host=<rds-proxy-endpoint> port=5432 dbname=onlineticketingsystem user=<master-or-bootstrap-user> sslmode=require"'
  exit 1
fi

APP_DB_NAME=${APP_DB_NAME:-onlineticketingsystem}
APP_DB_USER=${APP_DB_USER:-app_user}
SEED_DATA=${SEED_DATA:-1}
CURRENCY=${CURRENCY:-INR}
EVENTS_TO_CREATE=${EVENTS_TO_CREATE:-10}
SEATS_PER_CATEGORY=${SEATS_PER_CATEGORY:-1000}
MIN_CATEGORIES_PER_EVENT=${MIN_CATEGORIES_PER_EVENT:-2}

if [ "$MIN_CATEGORIES_PER_EVENT" -lt 2 ]; then
  echo "ERROR: MIN_CATEGORIES_PER_EVENT must be at least 2"
  exit 1
fi

if [ "$SEATS_PER_CATEGORY" -lt 1000 ]; then
  echo "ERROR: SEATS_PER_CATEGORY must be at least 1000 to satisfy seed requirement"
  exit 1
fi

if [ "$EVENTS_TO_CREATE" -lt 10 ]; then
  echo "ERROR: EVENTS_TO_CREATE must be at least 10 to satisfy seed requirement"
  exit 1
fi

echo "Using config:"
echo "  APP_DB_NAME=$APP_DB_NAME"
echo "  APP_DB_USER=$APP_DB_USER"
echo "  SEED_DATA=$SEED_DATA"
echo "  CURRENCY=$CURRENCY"
echo "  EVENTS_TO_CREATE=$EVENTS_TO_CREATE"
echo "  SEATS_PER_CATEGORY=$SEATS_PER_CATEGORY"
echo "  MIN_CATEGORIES_PER_EVENT=$MIN_CATEGORIES_PER_EVENT"

echo "=================================================="

psql "$DB_CONN" \
  -v ON_ERROR_STOP=1 \
  -v APP_DB_NAME="$APP_DB_NAME" \
  -v APP_DB_USER="$APP_DB_USER" \
  -v SEED_DATA="$SEED_DATA" \
  -v CURRENCY="$CURRENCY" \
  -v EVENTS_TO_CREATE="$EVENTS_TO_CREATE" \
  -v SEATS_PER_CATEGORY="$SEATS_PER_CATEGORY" \
  -v MIN_CATEGORIES_PER_EVENT="$MIN_CATEGORIES_PER_EVENT" <<'SQL'

-- =============================================================================
-- 1) APP USER + IAM AUTH
-- =============================================================================
DO $$
DECLARE
  v_app_user text := :'APP_DB_USER';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_app_user) THEN
    EXECUTE format('CREATE USER %I LOGIN', v_app_user);
  END IF;
END $$;

DO $$
DECLARE
  v_app_user text := :'APP_DB_USER';
BEGIN
  EXECUTE format('GRANT rds_iam TO %I', v_app_user);
  EXECUTE format('GRANT CONNECT ON DATABASE %I TO %I', :'APP_DB_NAME', v_app_user);
  EXECUTE format('GRANT USAGE ON SCHEMA public TO %I', v_app_user);
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO %I', v_app_user);
  EXECUTE format('GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO %I', v_app_user);
  EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO %I', v_app_user);
  EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO %I', v_app_user);
END $$;

-- =============================================================================
-- 2) EXTENSIONS + TYPES
-- =============================================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;

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

-- =============================================================================
-- 3) CORE TABLES
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.venues (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  location_id UUID NOT NULL REFERENCES public.locations(id) ON DELETE RESTRICT,
  name TEXT NOT NULL,
  address TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_venues_location_name UNIQUE (location_id, name)
);

CREATE TABLE IF NOT EXISTS public.performers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  venue_id UUID NOT NULL REFERENCES public.venues(id) ON DELETE RESTRICT,
  event_date TIMESTAMPTZ NOT NULL,
  event_time TIME,
  event_type TEXT,
  status event_status NOT NULL DEFAULT 'DRAFT',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_events_name_venue_date UNIQUE (name, venue_id, event_date)
);

CREATE TABLE IF NOT EXISTS public.event_performers (
  event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  performer_id UUID NOT NULL REFERENCES public.performers(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (event_id, performer_id)
);

-- =============================================================================
-- 4) CATEGORIES + SEATS
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.event_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  price BIGINT NOT NULL CHECK (price >= 0),
  currency TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_event_category_name UNIQUE (event_id, name)
);

CREATE TABLE IF NOT EXISTS public.seats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  category_id UUID NOT NULL REFERENCES public.event_categories(id) ON DELETE CASCADE,
  seat_label TEXT NOT NULL,
  status seat_status NOT NULL DEFAULT 'AVAILABLE',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  booked_at TIMESTAMPTZ,
  CONSTRAINT uq_seats_event_label UNIQUE (event_id, seat_label)
);

CREATE INDEX IF NOT EXISTS idx_seats_event_category_status
  ON public.seats(event_id, category_id, status);

CREATE INDEX IF NOT EXISTS idx_seats_event_category
  ON public.seats(event_id, category_id);

-- =============================================================================
-- 5) RESERVATIONS + RESERVATION_SEATS
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.reservations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE RESTRICT,
  category_id UUID NOT NULL REFERENCES public.event_categories(id) ON DELETE RESTRICT,
  status reservation_status NOT NULL DEFAULT 'HOLD',
  idempotency_key TEXT,
  expires_at TIMESTAMPTZ,
  failure_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_reservation_user_event_idempotency UNIQUE (user_id, event_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_reservations_event_category_status
  ON public.reservations(event_id, category_id, status);

CREATE TABLE IF NOT EXISTS public.reservation_seats (
  reservation_id UUID NOT NULL REFERENCES public.reservations(id) ON DELETE CASCADE,
  event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  seat_id UUID NOT NULL REFERENCES public.seats(id) ON DELETE CASCADE,
  status reservation_status NOT NULL DEFAULT 'HOLD',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (reservation_id, seat_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_active_reservation_per_seat
  ON public.reservation_seats(seat_id)
  WHERE status IN ('HOLD', 'CONFIRMED');

-- =============================================================================
-- 6) TICKETS
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.tickets (
  id UUID PRIMARY KEY,
  user_id TEXT NOT NULL,
  reservation_id UUID NOT NULL,
  payment_id UUID NOT NULL,
  event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE RESTRICT,
  category_id UUID NOT NULL REFERENCES public.event_categories(id) ON DELETE RESTRICT,
  venue_id UUID NOT NULL REFERENCES public.venues(id) ON DELETE RESTRICT,
  seat_label TEXT NOT NULL,
  unit_price BIGINT NOT NULL CHECK (unit_price >= 0),
  total_amount BIGINT NOT NULL CHECK (total_amount >= 0),
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

CREATE INDEX IF NOT EXISTS idx_tickets_reservation_id ON public.tickets(reservation_id);
CREATE INDEX IF NOT EXISTS idx_tickets_event_id       ON public.tickets(event_id);
CREATE INDEX IF NOT EXISTS idx_tickets_user_id        ON public.tickets(user_id);

-- =============================================================================
-- 7) HELPER FUNCTION TO KEEP updated_at FRESH
-- =============================================================================
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_locations_updated_at') THEN
    CREATE TRIGGER trg_locations_updated_at BEFORE UPDATE ON public.locations FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_venues_updated_at') THEN
    CREATE TRIGGER trg_venues_updated_at BEFORE UPDATE ON public.venues FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_performers_updated_at') THEN
    CREATE TRIGGER trg_performers_updated_at BEFORE UPDATE ON public.performers FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_events_updated_at') THEN
    CREATE TRIGGER trg_events_updated_at BEFORE UPDATE ON public.events FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_event_categories_updated_at') THEN
    CREATE TRIGGER trg_event_categories_updated_at BEFORE UPDATE ON public.event_categories FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_seats_updated_at') THEN
    CREATE TRIGGER trg_seats_updated_at BEFORE UPDATE ON public.seats FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_reservations_updated_at') THEN
    CREATE TRIGGER trg_reservations_updated_at BEFORE UPDATE ON public.reservations FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_reservation_seats_updated_at') THEN
    CREATE TRIGGER trg_reservation_seats_updated_at BEFORE UPDATE ON public.reservation_seats FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_tickets_updated_at') THEN
    CREATE TRIGGER trg_tickets_updated_at BEFORE UPDATE ON public.tickets FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
END $$;

-- =============================================================================
-- 8) SEED DATA (10+ EVENTS / MULTIPLE LOCATIONS / MULTIPLE VENUES / MULTIPLE PERFORMERS)
-- =============================================================================
DO $$
DECLARE
  v_seed_enabled integer := :'SEED_DATA';
  v_currency text := :'CURRENCY';
  v_events_to_create integer := :'EVENTS_TO_CREATE';
  v_seats_per_category integer := :'SEATS_PER_CATEGORY';
  v_min_categories integer := :'MIN_CATEGORIES_PER_EVENT';

  v_locations text[] := ARRAY[
    'Pune',
    'Mumbai',
    'Bengaluru',
    'Hyderabad',
    'Delhi NCR'
  ];

  v_venues text[] := ARRAY[
    'Grand Dome Arena',
    'City Pulse Stadium',
    'Skyline Convention Centre',
    'Riverfront Live Hall',
    'Metro Indoor Arena',
    'Summit Performance Bowl',
    'Cultural Square Auditorium',
    'Harbour View Arena',
    'Tech Park Amphitheatre',
    'Royal Exhibition Ground'
  ];

  v_addresses text[] := ARRAY[
    'Phase 1 Central Road',
    'Downtown Ring Road',
    'Tech District Main Boulevard',
    'Riverfront Cultural Street',
    'Metro Circle Business District',
    'Summit Peak Avenue',
    'Arts Square Residency Road',
    'Harbour Coastline Drive',
    'Innovation Park Avenue',
    'Heritage Plaza Main Road'
  ];

  v_performers text[] := ARRAY[
    'Aria Collective',
    'Neon Pulse',
    'Rhythm Forge',
    'Echo Assembly',
    'Blue Ember Ensemble',
    'Urban Sargam',
    'The Midnight Circuit',
    'Spectrum Voices',
    'Silver Stage Company',
    'Aurora Live Project',
    'Monsoon Beats',
    'Velocity Sessions'
  ];

  v_event_prefixes text[] := ARRAY[
    'Live Concert',
    'Stand-up Special',
    'Music Festival Night',
    'Stage Showcase',
    'Headline Performance',
    'Weekend Live',
    'Grand Tour Stop',
    'City Spotlight'
  ];

  v_event_types text[] := ARRAY[
    'Concert',
    'Comedy',
    'Festival',
    'Theatre',
    'Live Show'
  ];

  v_category_names text[] := ARRAY['VIP', 'General', 'Premium', 'Balcony'];
  v_category_prices bigint[] := ARRAY[4500, 1200, 2500, 1800];

  i integer;
  j integer;
  k integer;
  v_location_id uuid;
  v_venue_id uuid;
  v_event_id uuid;
  v_performer_id uuid;
  v_category_id uuid;
  v_event_name text;
  v_event_date timestamptz;
  v_event_time time;
  v_event_type text;
  v_category_name text;
  v_category_price bigint;
  v_row_prefix text;
  v_existing_events integer;
BEGIN
  IF v_seed_enabled <> 1 THEN
    RAISE NOTICE 'SEED_DATA != 1, skipping seed data';
    RETURN;
  END IF;

  IF v_events_to_create < 10 THEN
    RAISE EXCEPTION 'EVENTS_TO_CREATE must be at least 10';
  END IF;

  IF v_seats_per_category < 1000 THEN
    RAISE EXCEPTION 'SEATS_PER_CATEGORY must be at least 1000';
  END IF;

  -- Base dimensions -----------------------------------------------------------------
  FOR i IN 1 .. array_length(v_locations, 1) LOOP
    INSERT INTO public.locations(name)
    VALUES (v_locations[i])
    ON CONFLICT (name) DO NOTHING;
  END LOOP;

  FOR i IN 1 .. array_length(v_performers, 1) LOOP
    INSERT INTO public.performers(name)
    VALUES (v_performers[i])
    ON CONFLICT (name) DO NOTHING;
  END LOOP;

  -- Venues distributed across locations ----------------------------------------------
  FOR i IN 1 .. array_length(v_venues, 1) LOOP
    SELECT id INTO v_location_id
    FROM public.locations
    WHERE name = v_locations[((i - 1) % array_length(v_locations, 1)) + 1];

    INSERT INTO public.venues(location_id, name, address)
    VALUES (
      v_location_id,
      v_venues[i],
      v_addresses[i] || ', ' || v_locations[((i - 1) % array_length(v_locations, 1)) + 1]
    )
    ON CONFLICT (location_id, name) DO NOTHING;
  END LOOP;

  -- Events ---------------------------------------------------------------------------
  SELECT COUNT(*) INTO v_existing_events FROM public.events;

  FOR i IN 1 .. v_events_to_create LOOP
    SELECT v.id INTO v_venue_id
    FROM public.venues v
    ORDER BY v.name
    OFFSET ((i - 1) % (SELECT COUNT(*) FROM public.venues))
    LIMIT 1;

    v_event_name := v_event_prefixes[((i - 1) % array_length(v_event_prefixes, 1)) + 1] || ' ' || lpad(i::text, 2, '0');
    v_event_date := date_trunc('day', now()) + make_interval(days => (i * 3)) + interval '19 hours';
    v_event_time := (time '18:30:00' + (((i - 1) % 4) * interval '30 minutes'))::time;
    v_event_type := v_event_types[((i - 1) % array_length(v_event_types, 1)) + 1];

    INSERT INTO public.events(name, description, venue_id, event_date, event_time, event_type, status)
    VALUES (
      v_event_name,
      'Seeded demo event ' || i || ' for online ticketing system bootstrap',
      v_venue_id,
      v_event_date,
      v_event_time,
      v_event_type,
      'ON_SALE'
    )
    ON CONFLICT (name, venue_id, event_date) DO NOTHING;

    SELECT e.id INTO v_event_id
    FROM public.events e
    WHERE e.name = v_event_name
      AND e.venue_id = v_venue_id
      AND e.event_date = v_event_date
    LIMIT 1;

    -- attach 1 performer per event (stable, idempotent)
    SELECT p.id INTO v_performer_id
    FROM public.performers p
    ORDER BY p.name
    OFFSET ((i - 1) % (SELECT COUNT(*) FROM public.performers))
    LIMIT 1;

    INSERT INTO public.event_performers(event_id, performer_id)
    VALUES (v_event_id, v_performer_id)
    ON CONFLICT DO NOTHING;

    -- categories: always at least 2, can scale via MIN_CATEGORIES_PER_EVENT
    FOR j IN 1 .. GREATEST(v_min_categories, 2) LOOP
      v_category_name := v_category_names[j];
      v_category_price := v_category_prices[j];

      INSERT INTO public.event_categories(event_id, name, price, currency)
      VALUES (v_event_id, v_category_name, v_category_price, v_currency)
      ON CONFLICT (event_id, name) DO NOTHING;

      SELECT ec.id INTO v_category_id
      FROM public.event_categories ec
      WHERE ec.event_id = v_event_id
        AND ec.name = v_category_name
      LIMIT 1;

      -- seat labels are unique per event. Prefix by category for clarity.
      -- VIP     -> VIP-0001 ...
      -- General -> GEN-0001 ...
      -- Premium -> PRE-0001 ...
      -- Balcony -> BAL-0001 ...
      v_row_prefix := CASE v_category_name
        WHEN 'VIP' THEN 'VIP'
        WHEN 'General' THEN 'GEN'
        WHEN 'Premium' THEN 'PRE'
        WHEN 'Balcony' THEN 'BAL'
        ELSE upper(left(regexp_replace(v_category_name, '[^A-Za-z0-9]', '', 'g'), 3))
      END;

      INSERT INTO public.seats(event_id, category_id, seat_label, status)
      SELECT
        v_event_id,
        v_category_id,
        v_row_prefix || '-' || lpad(gs::text, 4, '0'),
        'AVAILABLE'::seat_status
      FROM generate_series(1, v_seats_per_category) AS gs
      ON CONFLICT (event_id, seat_label) DO NOTHING;
    END LOOP;
  END LOOP;
END $$;

-- =============================================================================
-- 9) VERIFICATION
-- =============================================================================
SELECT 'locations' AS object_name, count(*)::bigint AS row_count FROM public.locations
UNION ALL
SELECT 'venues', count(*)::bigint FROM public.venues
UNION ALL
SELECT 'performers', count(*)::bigint FROM public.performers
UNION ALL
SELECT 'events', count(*)::bigint FROM public.events
UNION ALL
SELECT 'event_performers', count(*)::bigint FROM public.event_performers
UNION ALL
SELECT 'event_categories', count(*)::bigint FROM public.event_categories
UNION ALL
SELECT 'seats', count(*)::bigint FROM public.seats
UNION ALL
SELECT 'reservations', count(*)::bigint FROM public.reservations
UNION ALL
SELECT 'reservation_seats', count(*)::bigint FROM public.reservation_seats
UNION ALL
SELECT 'tickets', count(*)::bigint FROM public.tickets
ORDER BY object_name;

SQL

echo "=================================================="
echo " DB Bootstrap completed successfully"
echo "=================================================="
