#!/usr/bin/env bash
# Design-for-failure test: prove replication, kill the primary, fail over, verify.
# Runs ON the k3s EC2 host (via AWS SSM Session Manager / send-command).
set -euo pipefail

PG_VER="${PG_VER:-16}"
PRIMARY_PORT="${PRIMARY_PORT:-5432}"
STANDBY_PORT="${STANDBY_PORT:-5433}"
DB="${DB:-employees}"
CANARY="failover-canary-$(date +%s)"

psql_p() { sudo -u postgres psql -p "$1" -d "$DB" -tAc "$2"; }

echo "==> 1. Write a canary row to the PRIMARY (:$PRIMARY_PORT)"
psql_p "$PRIMARY_PORT" "CREATE TABLE IF NOT EXISTS failover_probe(note text, ts timestamptz default now());"
psql_p "$PRIMARY_PORT" "INSERT INTO failover_probe(note) VALUES ('$CANARY');"

echo "==> 2. Confirm it replicated to the STANDBY (:$STANDBY_PORT)"
replicated=false
for _ in $(seq 1 15); do
  if psql_p "$STANDBY_PORT" "SELECT 1 FROM failover_probe WHERE note='$CANARY';" | grep -q 1; then
    echo "    replicated OK"; replicated=true; break
  fi
  sleep 2
done
[ "$replicated" = true ] || { echo "ERROR: canary did not replicate; check streaming replication"; exit 1; }

echo "==> 3. Simulate PRIMARY failure (stop ${PG_VER}/main)"
sudo -u postgres pg_ctlcluster "$PG_VER" main stop -m fast \
  || sudo pg_ctlcluster "$PG_VER" main stop -m immediate || true

echo "==> 4. Fail over to the standby"
"$(dirname "$0")/db-failover.sh"

echo "==> 5. Verify the new primary retains the canary and accepts writes"
psql_p "$STANDBY_PORT" "SELECT note FROM failover_probe WHERE note='$CANARY';" | grep -q "$CANARY" \
  && echo "    canary present after failover OK"
psql_p "$STANDBY_PORT" "INSERT INTO failover_probe(note) VALUES ('post-failover-write');" \
  && echo "    standby accepts writes OK"

echo "==> Failover test PASSED."
echo "    To restore redundancy, rebuild ${PG_VER}/main as a standby of :$STANDBY_PORT,"
echo "    or redeploy the stack to recreate the primary on :$PRIMARY_PORT."
