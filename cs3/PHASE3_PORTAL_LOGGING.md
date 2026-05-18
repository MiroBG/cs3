# Phase 3: Self-Service Portal & Logging Infrastructure

## Overview

Phase 3 implements a production-grade employee self-service portal with real-time log aggregation and visualization.

### Components

- **Portal Application**: Flask-based web application with Cognito OAuth integration
- **Container Registry**: AWS ECR for Docker image storage and lifecycle management
- **Logging Stack**: Loki + Fluentd + Grafana for centralized log collection
- **Kubernetes Manifests**: Deployment, Service, and NetworkPolicy resources

---

## Architecture

```
┌─────────────────┐
│  Cognito OAuth  │
│   (Phase 2)     │
└────────┬────────┘
         │
    ┌────▼────────────┐
    │ Portal (Flask)  │◄─┐
    │ - Auth          │  │ Kubernetes
    │ - Profile       │  │ Service
    │ - Requests      │  │ LoadBalancer
    └────┬────────────┘  │
         │                │
    ┌────▼────────────┐   │
    │ PostgreSQL      │   │
    │ - employees     │───┘
    │ - requests      │
    │ - audit_log     │
    └─────────────────┘

┌──────────────────────────────────┐
│     Logging Infrastructure       │
├──────────────────────────────────┤
│ Fluentd (log collector)          │
│  ▼                               │
│ Loki (log aggregation)           │
│  ▼                               │
│ Grafana (visualization)          │
└──────────────────────────────────┘
```

---

## Portal Application

### Setup & Installation

#### 1. Build Portal Image

```bash
# Using the provided script
./cs3/scripts/build-portal-image.sh \
    123456789012.dkr.ecr.eu-central-1.amazonaws.com/cs3-portal \
    latest

# Or manually with Docker
cd cs3/portal
docker build -t cs3-portal:latest .
docker tag cs3-portal:latest $ECR_REPOSITORY_URL:latest
docker push $ECR_REPOSITORY_URL:latest
```

#### 2. Deploy to Kubernetes

```bash
./cs3/scripts/deploy-portal.sh \
    $ECR_REPOSITORY_URL:latest \
    $COGNITO_CLIENT_ID \
    $COGNITO_CLIENT_SECRET \
    $COGNITO_DOMAIN \
    $RDS_HOST \
    $DB_PASSWORD
```

### Portal Features

#### Authentication (OAuth 2.0)
- Redirects to Cognito login page
- Exchanges authorization code for ID token
- Maintains JWT session in browser

#### User Dashboard
- **Profile Display**: Fetches employee data from PostgreSQL
  - Email, name, department, role, status
- **Request Submission**: Create new employee requests
  - Request type: equipment, access, leave, other
  - Description text
- **Request History**: View all submitted requests with status tracking

#### API Endpoints

```
GET  /api/health              # Health check (for Kubernetes probes)
GET  /api/profile             # Get current user's profile
GET  /api/requests            # List user's requests
POST /api/requests            # Create new request
GET  /logout                  # Logout and redirect to Cognito
```

### Environment Variables

```bash
FLASK_SECRET_KEY              # Secret key for session signing
COGNITO_CLIENT_ID             # OAuth app client ID
COGNITO_CLIENT_SECRET         # OAuth app client secret
COGNITO_DOMAIN                # Cognito domain name
DB_HOST                       # PostgreSQL hostname
DB_NAME                       # Database name (employees)
DB_USER                       # Database user (admin)
DB_PASSWORD                   # Database password
DB_PORT                       # Database port (5432)
PORTAL_URL                    # Portal hostname (https://portal.innovatech.local)
AWS_REGION                    # AWS region (eu-central-1)
```

---

## Logging Infrastructure

### Components

#### Fluentd
- **Role**: Collects logs from Kubernetes containers
- **Input**: /var/log/containers/*.log
- **Filter**: Kubernetes metadata enrichment
- **Output**: Sends logs to Loki and stdout

#### Loki
- **Role**: Log aggregation and indexing
- **Storage**: Local volume (10Gi persistent storage)
- **Query Language**: LogQL for log filtering
- **Retention**: 7 days (configurable)

#### Grafana
- **Role**: Log visualization and dashboards
- **Data Source**: Loki
- **Default Credentials**: 
  - Username: `admin`
  - Password: Set via `grafana_admin_password` variable
- **Access**: http://grafana.logging:80 (within cluster)

### Installation (via Helm)

The logging stack is installed automatically by the `logging` Terraform module using Helm:

```bash
# Manually (if needed)
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install loki-stack grafana/loki-stack \
  --namespace logging \
  --create-namespace \
  --values values.yaml
```

### Fluentd Configuration

**File**: `cs3/terraform/logging/fluent-bit.conf`

```
[INPUT]
    Name              tail
    Path              /var/log/containers/*.log
    Parser            docker
    Tag               kube.*

[FILTER]
    Name                kubernetes
    Match               kube.*
    Kube_URL            https://kubernetes.default.svc:443
    Merge_Log           On

[OUTPUT]
    Name   loki
    Match  kube.*
    Host   loki
    Port   3100
    Labels job=fluentd
```

### Querying Logs

#### Via Grafana Web UI
1. Access Grafana dashboard: `http://grafana.logging:80`
2. Select "Explore" → "Loki" as data source
3. Use LogQL queries:

```logql
# All portal logs
{job="fluentd", pod="cs3-portal-*"}

# Error logs only
{job="fluentd", pod="cs3-portal-*"} |= "ERROR"

# Logs from specific namespace
{namespace="default"}

# Failed requests (HTTP 5xx)
{job="fluentd"} |= "500|502|503|504"
```

#### Via Loki API (CLI)
```bash
# Query recent logs
curl -G -s "http://loki:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={job="fluentd"}' \
  --data-urlencode 'start=<unix_timestamp>' | jq .

# Label values
curl -s "http://loki:3100/loki/api/v1/labels"
```

---

## Database Schema Updates

### New Table: employee_requests

Stores self-service requests submitted via the portal:

```sql
CREATE TABLE employee_requests (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL,
    request_type VARCHAR(50) NOT NULL,        -- equipment, access, leave, other
    description TEXT NOT NULL,
    status VARCHAR(50) DEFAULT 'pending',     -- pending, approved, denied, resolved
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now(),
    resolved_at TIMESTAMP,                    -- When request was resolved
    resolved_by VARCHAR(255)                  -- HR or admin who resolved
);

CREATE INDEX idx_request_email ON employee_requests(email);
CREATE INDEX idx_request_status ON employee_requests(status);
```

---

## Terraform Modules

### ECR Module

**Location**: `cs3/terraform/ecr/`

Manages container registry and CloudWatch logs:

```hcl
module "ecr" {
  source = "./ecr"
  
  name_prefix  = "cs3"
  cluster_name = "cs3-eks-cluster"
  tags         = var.tags
}
```

**Outputs**:
- `ecr_repository_url`: Full ECR repository URI
- `ecr_repository_name`: Repository name
- `cloudwatch_log_group`: CloudWatch log group for portal

### Logging Module

**Location**: `cs3/terraform/logging/`

Deploys Loki + Fluentd + Grafana via Helm:

```hcl
module "logging" {
  source = "./logging"
  
  logging_namespace      = "logging"
  grafana_admin_password = var.grafana_admin_password
  tags                   = var.tags
}
```

**Outputs**:
- `loki_endpoint`: Loki service endpoint
- `grafana_endpoint`: Grafana service endpoint
- `grafana_admin_user`: Admin username
- `grafana_admin_password`: Admin password (sensitive)

---

## Kubernetes Manifests

### Deployment

**File**: `cs3/k8s/portal/deployment.yaml`

- **Replicas**: 2 (for high availability)
- **Image**: ECR repository URL
- **Port**: 5000 (Flask default)
- **Resources**: 100m CPU / 256Mi memory (request), 500m / 512Mi (limit)
- **Health Checks**:
  - Readiness: `/api/health` every 10s
  - Liveness: `/api/health` every 30s (after 30s startup grace)

### Service

**File**: `cs3/k8s/portal/service.yaml`

- **Type**: LoadBalancer
- **Target Port**: 5000
- **Public Port**: 80
- **Network Policy**: Allows ingress traffic from all namespaces

### Secrets & ConfigMaps

**Secrets** (created by deployment script):
- `flask-secret-key`: Flask session signing key
- `cognito-client-id`: OAuth client ID
- `cognito-client-secret`: OAuth client secret
- `db-host`: RDS hostname
- `db-password`: RDS password

**ConfigMaps**:
- `cognito-domain`: Cognito domain name
- `portal-url`: Portal public URL

---

## GitHub Actions CI/CD Pipeline

### Workflow Steps

1. **check** (all events)
   - `terraform fmt -check`
   - `terraform init -backend=false`
   - `terraform validate`

2. **plan** (pull requests only)
   - AWS OIDC authentication
   - `terraform plan` with S3 backend + DynamoDB locks
   - Artifact upload for review

3. **apply** (main push only)
   - AWS OIDC authentication
   - `terraform apply -auto-approve`
   - Outputs ECR URL, EKS cluster, Cognito details

4. **build-and-push-image** (main push only)
   - ECR login
   - Build portal Docker image
   - Push to ECR with git SHA and `latest` tags

5. **database-init** (main push only)
   - Gets RDS endpoint from Terraform
   - Runs schema initialization via psql

6. **deploy-portal** (main push only)
   - Retrieves Terraform outputs
   - Updates kubeconfig
   - Deploys portal to Kubernetes
   - Verifies deployment rollout

### Required GitHub Secrets

```
AWS_ROLE_TO_ASSUME          # OIDC role ARN (arn:aws:iam::...:role/...)
TF_BACKEND_BUCKET           # S3 bucket for Terraform state
CS3_DB_PASSWORD             # PostgreSQL admin password
GRAFANA_ADMIN_PASSWORD      # Grafana admin password
```

---

## Manual Deployment Steps

### 1. Deploy Infrastructure

```bash
cd cs3/terraform

# Initialize with S3 backend
terraform init \
  -backend-config="bucket=cs3-tf-state" \
  -backend-config="key=cs3/terraform.tfstate" \
  -backend-config="region=eu-central-1" \
  -backend-config="dynamodb_table=terraform-locks"

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply
```

### 2. Get Outputs

```bash
export ECR_URL=$(terraform output -raw ecr_repository_url)
export CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
export COGNITO_CLIENT_ID=$(terraform output -raw cognito_client_id)
export COGNITO_CLIENT_SECRET=$(terraform output -raw cognito_client_secret)
export COGNITO_DOMAIN=$(terraform output -raw cognito_domain)
export RDS_HOST=$(terraform output -raw rds_endpoint | cut -d: -f1)
```

### 3. Build Portal Image

```bash
cd cs3

# Authenticate with ECR
aws ecr get-login-password --region eu-central-1 | \
  docker login --username AWS --password-stdin $ECR_URL

# Build and push
./scripts/build-portal-image.sh $ECR_URL latest
```

### 4. Connect to EKS

```bash
aws eks update-kubeconfig \
  --region eu-central-1 \
  --name $CLUSTER_NAME
```

### 5. Initialize Database

```bash
# Set environment for psql
export PGHOST=$(echo $RDS_ENDPOINT | cut -d: -f1)
export PGDATABASE=employees
export PGUSER=admin
export PGPASSWORD=<your-db-password>

# Apply schema
psql -f terraform/rds/schema.sql
```

### 6. Deploy Portal

```bash
./scripts/deploy-portal.sh \
  "$ECR_URL:latest" \
  "$COGNITO_CLIENT_ID" \
  "$COGNITO_CLIENT_SECRET" \
  "$COGNITO_DOMAIN" \
  "$RDS_HOST" \
  "$PGPASSWORD"
```

### 7. Verify Deployment

```bash
# Check pods
kubectl get pods -l app=cs3-portal

# Check service
kubectl get svc cs3-portal-svc

# Get LoadBalancer IP/hostname
kubectl get svc cs3-portal-svc -o wide

# View logs
kubectl logs -f deployment/cs3-portal
```

---

## Monitoring & Troubleshooting

### Health Check

```bash
# Via portal endpoint
curl http://<load-balancer-ip>/api/health

# Via kubectl
kubectl logs deployment/cs3-portal
kubectl describe pod -l app=cs3-portal
```

### Log Queries

#### Common Issues

```logql
# Portal startup errors
{pod="cs3-portal-*"} |= "ERROR" | json | level="error"

# Database connection failures
{pod="cs3-portal-*"} |= "database" |= "error"

# Cognito authentication issues
{pod="cs3-portal-*"} |= "OAuth" |= "failed"

# Performance: slow requests
{pod="cs3-portal-*"} | json | duration > 1000
```

#### View Logs in Real-time

```bash
# Via kubectl
kubectl logs -f deployment/cs3-portal --all-containers=true

# Via Loki CLI
logcli query \
  --addr=http://loki:3100 \
  '{pod="cs3-portal-*"}'
```

### Common Issues

| Issue | Solution |
|-------|----------|
| Pod not starting | Check `kubectl describe pod` for ImagePullBackOff or resource constraints |
| Database connection timeout | Verify RDS security group allows port 5432 from EKS security group |
| Cognito login fails | Confirm callback URLs match in deployment manifest |
| Grafana can't connect to Loki | Check namespace DNS: `http://loki.logging:3100` |
| Logs not appearing in Grafana | Verify Fluentd pod is running: `kubectl get pods -n logging` |

---

## Cost Analysis

| Component | Monthly Cost | Notes |
|-----------|-------------|-------|
| ECR Storage | ~$2 | 1GB of images, $0.10/GB/month |
| CloudWatch Logs | ~$3 | 10GB/month at $0.50/GB ingestion |
| Loki Storage | Included | 10Gi PVC in cluster |
| Grafana (Helm) | Included | Single pod in EKS cluster |
| **Total Phase 3** | **~$5/month** | Minimal overhead |
| **Total Phases 1-3** | **~$139/month** | EKS $73 + Node $17 + RDS $12 + NAT $32 + Phase 3 $5 |

---

## Security Considerations

### Portal
- ✅ OAuth 2.0 authentication via Cognito
- ✅ Session tokens stored in secure cookies (HttpOnly, Secure flags)
- ✅ CSRF protection via Flask-Session
- ✅ Input validation on request descriptions
- ✅ Database credentials injected as secrets (never in code)

### Logging
- ✅ Logs stored in encrypted EBS volumes
- ✅ Access to Grafana restricted by Kubernetes RBAC
- ✅ Sensitive data (passwords) not logged
- ✅ Log retention set to 7 days

### Container Registry
- ✅ ECR scan on push enabled
- ✅ Lifecycle policy: keep last 10 images
- ✅ IAM role-based access control
- ✅ Registry encryption enabled

---

## Next Steps (Phase 4)

- Integration tests for portal API
- Security hardening (WAF, network policies, RBAC)
- Performance testing and autoscaling
- Monitoring dashboards (Prometheus + Grafana)
- Operational runbooks and documentation
- Cost optimization review
