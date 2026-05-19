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
PERFORMER_NAME=${PERFORMER_NAME:-Demo Performer}
EVENT_NAME=${EVENT_NAME:-Demo Event}
SEAT_COUNT=${SEAT_COUNT:-200}
VIP_PCT=${VIP_PCT:-20}

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
CREATE TABLE IF NOT EXISTS locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT UNIQUE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS venues (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  location_id UUID REFERENCES locations(id),
  name TEXT,
  UNIQUE(location_id, name)
);

CREATE TABLE IF NOT EXISTS performers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT UNIQUE
);

CREATE TABLE IF NOT EXISTS events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT,
  description TEXT,
  venue_id UUID REFERENCES venues(id),
  event_date TIMESTAMPTZ,
  status event_status DEFAULT 'DRAFT'
);

-- ALTER SAFE (your alter script)
ALTER TABLE events ADD COLUMN IF NOT EXISTS event_type TEXT;

-- =====================================
-- 4) CATEGORIES + SEATS
-- =====================================
CREATE TABLE IF NOT EXISTS event_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID REFERENCES events(id),
  name TEXT,
  price BIGINT
);

CREATE TABLE IF NOT EXISTS seats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID REFERENCES events(id),
  category_id UUID REFERENCES event_categories(id),
  seat_label TEXT,
  status seat_status DEFAULT 'AVAILABLE',
  UNIQUE(event_id, seat_label)
);

-- =====================================
-- 5) OPTIONAL SEED
-- =====================================
DO \$\$
DECLARE
  v_location_id UUID;
  v_venue_id UUID;
  v_event_id UUID;
  v_vip UUID;
  v_gen UUID;
BEGIN
IF $SEED = 1 THEN

  INSERT INTO locations(name)
  VALUES ('$LOCATION_NAME')
  ON CONFLICT DO NOTHING;

  SELECT id INTO v_location_id FROM locations WHERE name='$LOCATION_NAME';

  INSERT INTO venues(location_id, name)
  VALUES (v_location_id, '$VENUE_NAME')
  ON CONFLICT DO NOTHING;

  SELECT id INTO v_venue_id FROM venues WHERE name='$VENUE_NAME';

  INSERT INTO performers(name)
  VALUES ('$PERFORMER_NAME')
  ON CONFLICT DO NOTHING;

  INSERT INTO events(name, venue_id, event_date, status)
  VALUES ('$EVENT_NAME', v_venue_id, now() + interval '7 day', 'ON_SALE')
  ON CONFLICT DO NOTHING;

  SELECT id INTO v_event_id FROM events WHERE name='$EVENT_NAME';

  INSERT INTO event_categories(event_id, name, price)
  VALUES (v_event_id, 'VIP', 3000)
  ON CONFLICT DO NOTHING;

  INSERT INTO event_categories(event_id, name, price)
  VALUES (v_event_id, 'General', 500)
  ON CONFLICT DO NOTHING;

  SELECT id INTO v_vip FROM event_categories WHERE name='VIP';
  SELECT id INTO v_gen FROM event_categories WHERE name='General';

  FOR i IN 1..$SEAT_COUNT LOOP
    INSERT INTO seats(event_id, category_id, seat_label)
    VALUES (
      v_event_id,
      CASE WHEN (i*100/$SEAT_COUNT) <= $VIP_PCT THEN v_vip ELSE v_gen END,
      'A-' || LPAD(i::text, 4, '0')
    )
    ON CONFLICT DO NOTHING;
  END LOOP;

END IF;
END \$\$;

-- =====================================
-- 6) VERIFICATION
-- =====================================
SELECT 'tables_created' as status;

SQL

echo "=================================================="
echo "✅ DB Bootstrap DONE (single script)"
echo "=================================================="