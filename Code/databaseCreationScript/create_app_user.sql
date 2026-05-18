-- 1) create app user if not exists
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user') THEN
    CREATE USER app_user LOGIN;
  END IF;
END $$;

-- 2) allow IAM auth
GRANT rds_iam TO app_user;

-- 3) minimum permissions
GRANT CONNECT ON DATABASE onlineticketingsystem TO app_user;
GRANT USAGE ON SCHEMA public TO app_user;

GRANT SELECT, INSERT, UPDATE, DELETE
ON ALL TABLES IN SCHEMA public
TO app_user;

-- 4) future tables (created by current user)
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT, INSERT, UPDATE, DELETE
ON TABLES TO app_user;

-- 5) (recommended) for sequences / identity columns
GRANT USAGE, SELECT
ON ALL SEQUENCES IN SCHEMA public
TO app_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT USAGE, SELECT
ON SEQUENCES TO app_user;