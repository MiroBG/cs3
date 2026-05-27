# Kubernetes Deployment Guide (CS3)

## Overview
This directory contains Kubernetes manifests for deploying the CS3 portal with full observability stack (Prometheus, Grafana, Loki, Fluentd) and security controls (RBAC, Network Policies).

## Directory Structure
- `00-namespace.yaml` — Pod security policies and namespace
- `portal/` — Portal deployment, service, ingress, HPA, config, secrets
- `rbac/` — ServiceAccounts, Roles, RoleBindings for portal, Prometheus, Fluentd
- `networkpolicies/` — Network segmentation and zero-trust rules
- `monitoring/` — Prometheus, Grafana deployments
- `logging/` — Loki, Fluentd deployments

## Prerequisites
- K8s cluster (managed or self-hosted)
- `kubectl` configured to target cluster
- Nginx Ingress Controller (for ingress)
- cert-manager (optional, for TLS)

## Quick Deploy
```bash
# Deploy all manifests
./scripts/deploy-k8s.sh cs3-prod

# Verify
kubectl get pods -n cs3-prod
kubectl get svc -n cs3-prod
```

## Configuration

### 1. Secrets
Edit `cs3/k8s/portal/deployment.yaml` and replace placeholders:
- `COGNITO_CLIENT_ID_VALUE` → from Cognito user pool
- `COGNITO_CLIENT_SECRET_VALUE` → from Cognito app client
- `DB_HOST_VALUE` → EC2 PostgreSQL endpoint or service DNS name
- `DB_PASSWORD_VALUE` → PostgreSQL password
- `FLASK_SECRET_KEY_VALUE` → random string

Or use `kubectl create secret`:
```bash
kubectl create secret generic portal-secrets \
  --from-literal=flask-secret-key=<key> \
  --from-literal=cognito-client-id=<id> \
  --from-literal=cognito-client-secret=<secret> \
  --from-literal=db-host=<host> \
  --from-literal=db-password=<password> \
  -n cs3-prod
```

### 2. Grafana
- Default credentials: `admin / admin` (change in `monitoring/grafana.yaml`)
- Access via port-forward: `kubectl port-forward -n cs3-prod svc/grafana 3000:3000`
- Open `http://localhost:3000`
- Datasources (Prometheus, Loki) auto-configured

### 3. Prometheus
- Scrapes metrics from pods with annotation `prometheus.io/scrape: "true"`
- Portal already annotated
- Add custom metrics to Flask app via Prometheus client library

### 4. Logging (Fluentd → Loki)
- Fluentd DaemonSet parses container logs
- Loki aggregates and indexes logs
- Query via Grafana Loki datasource or Loki API

## Monitoring & Observability

### Health Checks
Portal readiness probe: `GET /api/health` (must return 200)
Portal liveness probe: `GET /api/health`

### Scaling
HPA configured:
- Min replicas: 2
- Max replicas: 10
- CPU target: 70%
- Memory target: 80%

### Alerts (example)
Add to Prometheus:
```yaml
groups:
  - name: portal
    rules:
    - alert: PortalDown
      expr: up{job="portal"} == 0
      for: 1m
```

## Performance Testing (Flavor A)

For load testing:
```bash
# Deploy stack to K8s
kubectl apply -f cs3/k8s/portal/deployment.yaml

# Port-forward portal
kubectl port-forward -n cs3-prod svc/cs3-portal-svc 8080:80

# Run k6
K6_HOST=http://localhost:8080 k6 run cs3/load_tests/k6/portal_load_test.js
```

Monitor via Grafana dashboards.

## Troubleshooting

### Pod not starting
```bash
kubectl logs -n cs3-prod <pod-name>
kubectl describe pod -n cs3-prod <pod-name>
```

### Secrets not found
```bash
kubectl get secrets -n cs3-prod
kubectl describe secret portal-secrets -n cs3-prod
```

### Network policy too restrictive
Check policies:
```bash
kubectl get networkpolicy -n cs3-prod
kubectl describe networkpolicy <policy-name> -n cs3-prod
```

### Prometheus not scraping
- Ensure annotation `prometheus.io/scrape: "true"` on pod
- Check Prometheus targets UI: `http://localhost:9090/targets`

## Security Considerations

1. **Pod Security**: Namespace enforces restricted pod security
2. **RBAC**: ServiceAccounts limited to required permissions
3. **Network Policies**: Default deny-all with explicit allow rules
4. **Secrets**: Use external secret management (AWS Secrets Manager, Vault) in production
5. **Ingress TLS**: cert-manager auto-renews Let's Encrypt certs

## Cost Optimization

- Use `emptyDir` for ephemeral storage (Prometheus, Loki). For persistent storage, use PVC.
- Resource requests/limits set for cost predictability
- HPA scales down to min 2 replicas during low traffic
- Consider spot instances for non-critical workloads

## Next Steps

1. Configure external secret storage (Secrets Manager)
2. Add persistent volumes for Prometheus/Loki
3. Configure backup strategy for Prometheus/Loki data
4. Implement alerting (PagerDuty, Slack)
5. Set up log retention policies in Loki
