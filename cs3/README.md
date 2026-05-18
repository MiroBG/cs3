# CS3: Employee Lifecycle Management System

A comprehensive employee lifecycle management system built on AWS using Kubernetes, Cognito, PostgreSQL, and a Flask-based self-service portal with centralized logging.

## Phases Status

| Phase | Component | Status |
|-------|-----------|--------|
| **Phase 1** | Database & Infrastructure | ✅ Complete |
| **Phase 2** | Identity & Automation | ✅ Complete |
| **Phase 3** | Portal & Logging | ✅ Complete |
| **Phase 4** | Security & Operations | ⏳ Pending |

## Phase 1: Analysis, Design, and Foundation ✅

### Completed
- ✅ Terraform VPC with multi-AZ public/private/database subnets
- ✅ EKS Kubernetes cluster with managed node groups (t3.small, auto-scaling)
- ✅ RDS PostgreSQL 15.4 database with encryption and backups
- ✅ Employee schema with audit logging and request tracking tables
- ✅ Kubernetes portal manifests (Deployment & Service)
- ✅ CI/CD workflow foundation (GitHub Actions with OIDC)

## Phase 2: Employee Lifecycle Automation ✅

### Completed
- ✅ AWS Cognito integration for identity management
- ✅ User provisioning automation script (create Cognito users, database records)
- ✅ Employee de-provisioning workflow (disable accounts, mark offboarded)
- ✅ Audit logging for all provisioning/de-provisioning actions
- ✅ Python automation scripts for manual and batch provisioning
- ✅ GitHub Actions pipeline with OIDC authentication
- ✅ Database schema initialization via CI/CD

### Key Features
- **Automated Provisioning**: Create employee accounts in Cognito, database, and assign to groups
- **Automated De-provisioning**: Disable accounts, revoke access, mark employees offboarded
- **Audit Trail**: All lifecycle changes logged with timestamp and operator information
- **GitHub Actions Integration**: Deploy infrastructure and manage employees via CI/CD
- **Cognito Authentication**: Central identity provider for the self-service portal

## Phase 3: Self-Service Portal & Logging ✅

### Completed
- ✅ Flask-based employee self-service portal with OAuth 2.0
- ✅ Portal features: profile view, request submission, history tracking
- ✅ AWS ECR container registry with image lifecycle management
- ✅ Loki + Fluentd + Grafana logging stack
- ✅ Real-time log aggregation and visualization
- ✅ Kubernetes deployment with health checks and auto-scaling
- ✅ GitHub Actions pipeline for building and pushing container images

### Key Features
- **Portal Application**:
  - OAuth 2.0 authentication via Cognito
  - Employee profile dashboard with department and role info
  - Self-service request submission (equipment, access, leave)
  - Request history with status tracking
  - REST API with health checks for Kubernetes probes

- **Logging Infrastructure**:
  - Fluentd collects logs from all Kubernetes containers
  - Loki aggregates and indexes logs for fast retrieval
  - Grafana provides visualization and dashboards
  - LogQL query language for advanced log filtering
  - 7-day retention policy for compliance

- **Container Registry**:
  - ECR with automated image scanning on push
  - Lifecycle policy: keep last 10 images
  - CloudWatch integration for log tracking

## Directory Structure

```
cs3/
├── terraform/
│   ├── vpc/            # VPC, subnets, NAT, routing
│   ├── eks/            # Kubernetes cluster configuration
│   ├── rds/            # PostgreSQL employee database
│   ├── cognito/        # Identity provider setup (Phase 2)
│   ├── ecr/            # Container registry (Phase 3)
│   ├── logging/        # Loki, Fluentd, Grafana (Phase 3)
│   ├── main.tf         # Root Terraform configuration
│   ├── variables.tf    # Input variables
│   └── outputs.tf      # Output values for CI/CD
│
├── portal/             # Flask portal application (Phase 3)
│   ├── app.py          # Flask application with OAuth/API
│   ├── Dockerfile      # Container image definition
│   ├── requirements.txt # Python dependencies
│   └── templates/
│       └── dashboard.html  # Web UI
│
├── k8s/
│   └── portal/         # Kubernetes manifests for portal
│       ├── deployment.yaml  # Portal deployment with health checks
│       └── service.yaml     # LoadBalancer service and NetworkPolicy
│
├── scripts/
│   ├── provision_employee.py      # Onboarding automation (Phase 2)
│   ├── deprovision_employee.py    # Offboarding automation (Phase 2)
│   ├── build-portal-image.sh      # Docker build & push (Phase 3)
│   ├── deploy-portal.sh           # K8s deployment (Phase 3)
│   └── requirements.txt           # Python dependencies
│
├── .github/
│   └── workflows/
│       └── cs3_deploy.yml         # GitHub Actions CI/CD pipeline
│
├── PHASE1_DATABASE.md             # Phase 1 documentation
├── PHASE2_AUTOMATION.md           # Phase 2 documentation
├── PHASE3_PORTAL_LOGGING.md       # Phase 3 documentation
└── README.md                      # This file
```

## GitHub Actions Deployment Pipeline

The CS3 CI/CD pipeline uses GitHub OIDC for secure, credential-free deployments:

### Triggers
- **Pull requests** affecting `cs3/**` — Plan only (no apply)
- **Push to main** — Plan, apply, and initialize database
- **Manual dispatch** — Allows manual triggering from GitHub UI

### Pipeline Stages

1. **Validation** (`check` job)
   - `terraform fmt -check` — Verify code formatting
   - `terraform init -backend=false` — Initialize without backend
   - `terraform validate` — Check syntax and resource types

2. **Plan** (`plan` job, PR only)
   - Configures AWS credentials via OIDC
   - Generates `tfplan` artifact
   - Uploads for review

3. **Apply** (`apply` job, main branch only)
   - Assumes AWS role via OIDC
   - Configures S3 backend and DynamoDB locks
   - Runs `terraform apply` for infrastructure
   - Outputs Cognito and RDS endpoints

4. **Database Init** (`database-init` job, main branch only)
   - Retrieves RDS endpoint from Terraform state
   - Initializes employee database schema
   - Creates sample employees for testing

### Required GitHub Secrets

Store these in the repository settings:

| Secret | Description |
|--------|-------------|
| `AWS_ROLE_TO_ASSUME` | IAM role ARN for OIDC assume role (can also use Variable) |
| `TF_BACKEND_BUCKET` | S3 bucket for Terraform state (can also use Variable) |
| `CS3_DB_PASSWORD` | RDS master password (**must be Secret, not Variable**) |

Optional:
| Secret | Description |
|--------|-------------|
| `CS3_COGNITO_CALLBACK_URL` | Portal callback URL for OAuth (can use Variable) |

### GitHub Variables (Optional)

These can be set as Variables if not sensitive:
- `AWS_ROLE_TO_ASSUME` — Same as Secret above
- `TF_BACKEND_BUCKET` — Same as Secret above
- `CS3_COGNITO_CALLBACK_URL` — Portal URL for Cognito OAuth

## Deployment Instructions

### 1. Set Up AWS OIDC Trust

Create an IAM role that GitHub Actions can assume:

```bash
aws iam create-role \
  --role-name github-actions-cs3 \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Federated": "arn:aws:iam::<ACCOUNT>:oidc-provider/token.actions.githubusercontent.com"
        },
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Condition": {
          "StringEquals": {
            "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
            "token.actions.githubusercontent.com:sub": "repo:<OWNER>/<REPO>:ref:refs/heads/main"
          }
        }
      }
    ]
  }'
```

Attach policies for Terraform and RDS access:
```bash
aws iam attach-role-policy \
  --role-name github-actions-cs3 \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

### 2. Create S3 Backend and DynamoDB Lock Table

```bash
# Create S3 bucket for state
aws s3api create-bucket \
  --bucket cs3-terraform-state-$(date +%s) \
  --region eu-central-1 \
  --create-bucket-configuration LocationConstraint=eu-central-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket <BUCKET_NAME> \
  --versioning-configuration Status=Enabled

# Create DynamoDB lock table
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --region eu-central-1
```

### 3. Configure GitHub Repository Secrets

```bash
# Set repository secrets
gh secret set AWS_ROLE_TO_ASSUME -b "arn:aws:iam::<ACCOUNT>:role/github-actions-cs3"
gh secret set TF_BACKEND_BUCKET -b "<BUCKET_NAME>"
gh secret set CS3_DB_PASSWORD -b "$(openssl rand -base64 24)"
```

### 4. Deploy via GitHub Actions

Push to main or manually trigger:
```bash
git push origin main
```

Monitor the workflow in GitHub Actions. After successful apply, Terraform outputs will be available for use with provisioning scripts.

## Provisioning Employees via GitHub Actions

After deployment, provision employees using GitHub Secrets:

```bash
# Get outputs from GitHub Actions job logs
export COGNITO_POOL_ID=$(gh run view <RUN_ID> --json jobs -q '.jobs[].steps[] | select(.name=="Output Terraform values").summary' | jq -r '.cognito_user_pool_id')
export RDS_HOST=$(gh run view <RUN_ID> --json jobs -q '.jobs[].steps[] | select(.name=="Output Terraform values").summary' | jq -r '.rds_endpoint' | cut -d: -f1)

# Run provisioning script
python3 cs3/scripts/provision_employee.py \
  --user-pool-id $COGNITO_POOL_ID \
  --db-host $RDS_HOST \
  --db-name employees \
  --db-user admin \
  --db-password ${{ secrets.CS3_DB_PASSWORD }} \
  --email john.doe@innovatech.local \
  --name "John Doe" \
  --department "Engineering"
```

## Manual Provisioning

To provision employees without CI/CD:

```bash
# 1. Get Terraform outputs
cd cs3/terraform
terraform init -backend-config="..." # Configure backend
terraform output

# 2. Run provisioning script
export COGNITO_POOL_ID=$(terraform output -raw cognito_user_pool_id)
export RDS_HOST=$(terraform output -raw rds_endpoint | cut -d: -f1)
export DB_PASSWORD="<PASSWORD>"

python3 ../scripts/provision_employee.py \
  --user-pool-id $COGNITO_POOL_ID \
  --db-host $RDS_HOST \
  --db-name employees \
  --db-user admin \
  --db-password $DB_PASSWORD \
  --email jane.smith@innovatech.local \
  --name "Jane Smith" \
  --department "Operations"
```

## Provisioning and De-provisioning Examples

### Provision Single Employee
```bash
python3 cs3/scripts/provision_employee.py \
  --user-pool-id us-east-1_abc123def456 \
  --db-host cs3-employee-db.abcd1234.eu-central-1.rds.amazonaws.com \
  --db-name employees \
  --db-user admin \
  --db-password "SecurePassword123!" \
  --email john.doe@innovatech.local \
  --name "John Doe" \
  --department "Engineering" \
  --role employee \
  --group employees
```

### Deprovision Employee
```bash
python3 cs3/scripts/deprovision_employee.py \
  --user-pool-id us-east-1_abc123def456 \
  --db-host cs3-employee-db.abcd1234.eu-central-1.rds.amazonaws.com \
  --db-name employees \
  --db-user admin \
  --db-password "SecurePassword123!" \
  --email john.doe@innovatech.local
```

## Phase 3: Self-Service Portal Application (Next)

Remaining work:
- [ ] Implement real portal application (replace nginx)
- [ ] Portal API backend for employee requests
- [ ] Logging pipeline (Loki + Fluentd integration)
- [ ] Self-service request workflows (access requests, equipment ordering)
- [ ] Portal integration with Cognito for authentication

## Phase 4: Testing, Security & Operations (Final)

- [ ] End-to-end integration tests
- [ ] Security hardening (network policies, RBAC, WAF rules)
- [ ] Monitoring dashboards (Prometheus + Grafana)
- [ ] Operational runbooks
- [ ] Cost analysis and performance recommendations

## Cost Considerations

- **EKS Control Plane**: ~$0.10/hour (~$73/month)
- **EKS Node Group** (1 t3.small): ~$0.023/hour (~$17/month)
- **RDS** (t3.micro): ~$0.017/hour (~$12/month)
- **NAT Gateway**: ~$0.045/hour (~$32/month)
- **Total**: ~$134/month for minimal production setup

To reduce costs:
- Use Spot instances for non-critical workloads
- Enable auto-scaling to reduce baseline nodes
- Use Reserved Instances for sustained usage
- Consider self-managed k3s for lowest cost alternative

## References

- [PHASE1_DATABASE.md](PHASE1_DATABASE.md) — Database architecture and setup
- [PHASE2_AUTOMATION.md](PHASE2_AUTOMATION.md) — Provisioning automation details
- [docs/cs3_requirement_analysis.typ](../docs/cs3_requirement_analysis.typ) — Requirement specifications
- [docs/cs3_design_implementation.typ](../docs/cs3_design_implementation.typ) — Architecture and design decisions
