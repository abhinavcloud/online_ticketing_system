
#!/bin/bash
set -euxo pipefail
dnf -y install postgresql15 || dnf -y install postgresq

psql -h onlineticketingsystem.cluster-chy0sq2si9a2.ap-south-1.rds.amazonaws.com \
  -p 5432 \
  -U abhinavkumar1987 \
  -d onlineticketingsystem \
  --set=sslmode=require \
  -v seed=1 \
  -f ticketing_bootstrap.sql



psql -h onlineticketingsystem.cluster-chy0sq2si9a2.ap-south-1.rds.amazonaws.com \
  -p 5432 \
  -U abhinavkumar1987 \
  -d onlineticketingsystem \
  --set=sslmode=require \
  -v seed=1 \
  -v event_name='Concert 1' \
  -v seat_prefix='B' \
  -v seat_count=500 \
  -f ticketing_bootstrap.sql
