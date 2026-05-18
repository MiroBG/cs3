# CS3 Phase 1: Database Implementation

## Employee Lifecycle Database

The CS3 system uses Amazon RDS PostgreSQL to store employee lifecycle data for onboarding and offboarding management.

### Database Schema

The employee database includes two main tables:

#### `employees` table
Stores core employee information for the onboarding/offboarding process:
- **id** (SERIAL PRIMARY KEY): Unique employee identifier
- **email** (VARCHAR UNIQUE): Employee email address (primary lookup key)
- **name** (VARCHAR): Full employee name
- **department** (VARCHAR): Department assignment
- **status** (VARCHAR): Current status (active, pending, offboarded)
- **role** (VARCHAR): User role (admin, hr, employee)
- **created_at** (TIMESTAMP): Record creation time
- **updated_at** (TIMESTAMP): Last update time
- **offboarded_at** (TIMESTAMP): When the employee was offboarded (NULL if active)

#### `employee_audit_log` table
Tracks all lifecycle state changes for compliance and audit:
- **id** (SERIAL PRIMARY KEY): Log entry ID
- **employee_id** (INTEGER FK): Reference to employee
- **action** (VARCHAR): Action type (provision, deprovision, status_change)
- **old_status** (VARCHAR): Previous status
- **new_status** (VARCHAR): New status after action
- **timestamp** (TIMESTAMP): When the change occurred
- **performed_by** (VARCHAR): Who initiated the action

### Data Initialization

The schema is defined in `schema.sql` and includes:
- Table creation with proper constraints and indexes
- Indexes on common query fields (email, status, department)
- Sample data for testing (admin, HR manager, and two employees)

To apply the schema after Terraform creates the RDS instance:
```bash
psql -h <rds_endpoint> -U admin -d employees -f cs3/terraform/rds/schema.sql
```

### Terraform Configuration

The RDS module in `cs3/terraform/rds/` creates:
- PostgreSQL 15.4 instance (configurable)
- Database subnet group for multi-AZ availability
- Security group allowing PostgreSQL access from the VPC
- Automated backups (7 days retention by default)
- Optional read replica for high-availability scenarios

#### Key Variables
```hcl
db_username          = "admin"
db_password          = var.db_password              # Must be set at apply
db_instance_class    = "db.t3.micro"                # Configurable for cost/performance
db_allocated_storage = 20                           # GB
db_multi_az          = false                        # Enable for HA
create_read_replica  = false                        # Optional read replica
```

### Deployment

To apply the full Phase 1 infrastructure:

1. Generate a strong password for the database:
```bash
openssl rand -base64 24
```

2. Initialize Terraform:
```bash
cd cs3/terraform
terraform init
```

3. Plan and review:
```bash
terraform plan -var="db_password=<YOUR_PASSWORD>"
```

4. Apply infrastructure:
```bash
terraform apply -var="db_password=<YOUR_PASSWORD>"
```

5. Once the RDS instance is ready, initialize the schema:
```bash
# Get the RDS endpoint from Terraform output
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
psql -h ${RDS_ENDPOINT%:*} -U admin -d employees -f ../rds/schema.sql
```

### Security Considerations

- **Encryption**: Storage encryption is enabled by default
- **Backup**: Automated backups retained for 7 days
- **Network**: Database is in private subnets; only accessible from within the VPC
- **Secrets**: Master password is marked as sensitive in Terraform output
- **Access Control**: PostgreSQL access limited to VPC CIDR via security group

### Next Steps (Phase 2)

Once Phase 1 is complete, Phase 2 will add:
- Provisioning automation scripts that populate employee records
- Identity provider integration to sync cloud identities with database
- De-provisioning workflows to safely offboard employees
- RBAC policies to control who can view/modify employee data
