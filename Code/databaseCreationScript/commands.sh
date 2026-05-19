#!/bin/bash
set -euo pipefail

# ----------------------------
# CONFIG (edit if required)
# ----------------------------

# Where your bootstrap script is located
BOOTSTRAP_SCRIPT="${BOOTSTRAP_SCRIPT:-./bootstrap_db_schema.sh}"

# If bootstrap_db_schema.sh expects DB_CONN env var, set it here (optional)
# export DB_CONN="host=... port=5432 dbname=... user=... sslmode=require"

# ----------------------------
# 1) Validate bootstrap script exists
# ----------------------------
if [[ ! -f "$BOOTSTRAP_SCRIPT" ]]; then
  echo "❌ ERROR: Bootstrap script not found at: $BOOTSTRAP_SCRIPT"
  echo "Set BOOTSTRAP_SCRIPT env var or place bootstrap_db_schema.sh in current directory."
  exit 1
fi

# ----------------------------
# 2) Ensure psql exists; install if missing
# ----------------------------
if command -v psql >/dev/null 2>&1; then
  echo "✅ psql already installed: $(psql --version)"
else
  echo "⚠️ psql not found. Installing PostgreSQL client..."

  # Detect package manager
  if command -v dnf >/dev/null 2>&1; then
    sudo dnf -y install postgresql15
  elif command -v yum >/dev/null 2>&1; then
    # For older Amazon Linux
    sudo yum -y install postgresql
  elif command -v apt-get >/dev/null 2>&1; then
    # For Ubuntu/Debian
    sudo apt-get update -y
    sudo apt-get install -y postgresql-client
  else
    echo "❌ ERROR: No supported package manager found (dnf/yum/apt-get). Install psql manually."
    exit 1
  fi

  echo "✅ psql installed: $(psql --version)"
fi

# ----------------------------
# 3) Run bootstrap script
# ----------------------------
echo "▶ Running bootstrap script: $BOOTSTRAP_SCRIPT"
chmod +x "$BOOTSTRAP_SCRIPT"
"$BOOTSTRAP_SCRIPT"

echo "✅ Done."
