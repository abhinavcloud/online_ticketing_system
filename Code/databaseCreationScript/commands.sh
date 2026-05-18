#!/bin/bash
set -euxo pipefail
dnf -y install postgresql15 || dnf -y install postgresq

psql "host=onlineticketingsystem.cluster-chy0sq2si9a2.ap-south-1.rds.amazonaws.com port=5432 dbname=onlineticketingsystem user=abhinavkumar1987 sslmode=require" \
  -v seed=1 \
  -v location_name='Pune' \
  -v venue_name='Big Arena' \
  -v performer_name='Demo Performer' \
  -v event_name='Demo Event' \
  -v seat_count=200 \
  -v vip_pct=20 \
  -f ticketing_bootstrap.sql
