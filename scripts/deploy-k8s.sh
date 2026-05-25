#!/usr/bin/env bash
set -euo pipefail

# Deploy K8s manifests to cluster
# Usage: ./deploy-k8s.sh [namespace]
# Example: ./deploy-k8s.sh cs3-prod

NAMESPACE="${1:-cs3-prod}"
K8S_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../cs3/k8s" && pwd)"

echo "Deploying K8s manifests to namespace: $NAMESPACE"

# Apply in order: namespace → rbac → networkpolicies → monitoring → logging → portal
echo "1. Creating namespace"
kubectl apply -f "$K8S_DIR/00-namespace.yaml"

echo "2. Applying RBAC (roles, service accounts)"
kubectl apply -f "$K8S_DIR/rbac/"

echo "3. Applying network policies"
kubectl apply -f "$K8S_DIR/networkpolicies/"

echo "4. Applying monitoring (Prometheus, Grafana)"
kubectl apply -f "$K8S_DIR/monitoring/"

echo "5. Applying logging (Loki, Fluentd)"
kubectl apply -f "$K8S_DIR/logging/"

echo "6. Applying portal deployment, service, ingress, HPA"
kubectl apply -f "$K8S_DIR/portal/"

echo ""
echo "=== Deployment Status ==="
kubectl get pods -n "$NAMESPACE"
kubectl get svc -n "$NAMESPACE"
echo ""
echo "Access Grafana (if using port-forward):"
echo "  kubectl port-forward -n $NAMESPACE svc/grafana 3000:3000"
echo "  Open http://localhost:3000 (admin/admin)"
