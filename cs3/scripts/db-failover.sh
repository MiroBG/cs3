#!/usr/bin/env bash
# Promote the local standby PostgreSQL cluster to primary and repoint the portal.
# Runs ON the k3s EC2 host (e.g. via AWS SSM Session Manager / send-command).
#
# Single-vCPU constraint: the standby runs on the SAME node (port 5433), so this
# is logical failover, not node-level HA. See the Phase 4 operations runbook.
set -euo pipefail

PG_VER="${PG_VER:-16}"
STANDBY_PORT="${STANDBY_PORT:-5433}"
NAMESPACE="${NAMESPACE:-cs3-prod}"
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

is_primary() {
  sudo -u postgres psql -p "$STANDBY_PORT" -tAc "SELECT NOT pg_is_in_recovery();" 2>/dev/null | grep -q t
}

echo "==> Current PostgreSQL clusters:"
pg_lsclusters || true

if is_primary; then
  echo "==> Standby on :$STANDBY_PORT is already a primary; skipping promote."
else
  echo "==> Promoting standby cluster ${PG_VER}/standby ..."
  sudo -u postgres pg_ctlcluster "$PG_VER" standby promote
fi

echo "==> Waiting for the standby to accept writes ..."
for _ in $(seq 1 30); do
  if is_primary; then
    echo "    standby promoted to primary on port ${STANDBY_PORT}"
    break
  fi
  sleep 2
done
is_primary || { echo "ERROR: standby did not become writable"; exit 1; }

echo "==> Repointing portal to DB port ${STANDBY_PORT} ..."
if command -v kubectl >/dev/null 2>&1; then
  kubectl -n "$NAMESPACE" set env deployment/cs3-portal DB_PORT="$STANDBY_PORT"
  kubectl -n "$NAMESPACE" rollout restart deployment/cs3-portal
  kubectl -n "$NAMESPACE" rollout status deployment/cs3-portal --timeout=180s
else
  echo "    kubectl not found; set DB_PORT=${STANDBY_PORT} on the portal manually."
fi

echo "==> Failover complete. New primary: 127.0.0.1:${STANDBY_PORT}"
