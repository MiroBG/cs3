# CS3 Phase 2: Employee Lifecycle Automation

Phase 2 implements automated provisioning and de-provisioning workflows using AWS Cognito for identity management and PostgreSQL for employee records.

## Architecture

### Identity Management (Cognito)

Cognito manages employee authentication and authorization:
- Central identity provider for portal login
- Multi-factor authentication (MFA) support
- Group-based access control
- OAuth 2.0 flows for portal integration
- Optional social login (Google, etc.)

### Provisioning Workflow

The provisioning process automates employee onboarding:

```
HR Request → Provision Script
  ├─ Create Cognito user account
  ├─ Create database record
  ├─ Assign to appropriate groups
  ├─ Log audit entry
  └─ Send welcome notification
```

### De-provisioning Workflow

The de-provisioning process automates employee offboarding:

```
HR Request → Deprovision Script
  ├─ Disable Cognito account
  ├─ Remove from all groups
  ├─ Mark as offboarded in database
  ├─ Log audit entry
  └─ Optional: Revoke IAM permissions
```

## Setup Instructions

### 1. Deploy Cognito Module

Add the Cognito module to your Terraform stack:

```bash
cd cs3/terraform
terraform init -upgrade
```

The Cognito module requires:
- `cognito_domain` — Globally unique domain name for the auth endpoint
- `identity_pool_id` — Cognito Identity Pool (created separately if needed)
- `employee_bucket_name` — S3 bucket for employee documents

Example Terraform variables:
```hcl
cognito_domain = "cs3-employees-prod"
```

### 2. Create Cognito Groups

Create groups for role-based access control:

```bash
aws cognito-idp create-group \
  --group-name employees \
  --user-pool-id <POOL_ID> \
  --description "Standard employee access"

aws cognito-idp create-group \
  --group-name hr-staff \
  --user-pool-id <POOL_ID> \
  --description "HR staff with provisioning access"

aws cognito-idp create-group \
  --group-name admins \
  --user-pool-id <POOL_ID> \
  --description "System administrators"
```

### 3. Install Python Dependencies

The provisioning scripts require boto3 and psycopg2:

```bash
pip install boto3 psycopg2-binary
```

Or use the requirements file:
```bash
pip install -r cs3/scripts/requirements.txt
```

## Provisioning an Employee

### Manual Provisioning

Provision a single employee with the script:

```bash
python3 cs3/scripts/provision_employee.py \
  --user-pool-id <COGNITO_POOL_ID> \
  --db-host <RDS_ENDPOINT> \
  --db-name employees \
  --db-user admin \
  --db-password <DB_PASSWORD> \
  --email john.doe@innovatech.local \
  --name "John Doe" \
  --department "Engineering" \
  --role employee \
  --group employees
```

The script will:
1. Create a Cognito user with a temporary password
2. Create a database record with the employee profile
3. Add the user to the specified Cognito group
4. Log the action in the audit table

Output example:
```
✓ Created Cognito user: john.doe@innovatech.local
✓ Created database record: john.doe@innovatech.local
✓ Added user john.doe@innovatech.local to group: employees

✓ Successfully provisioned: john.doe@innovatech.local
  Temporary password: aB3$cDef9GhIjKlM@nOpQrStU
  Department: Engineering
  Role: employee
```

### Batch Provisioning

For onboarding multiple employees, create a CSV file and iterate:

```bash
#!/bin/bash

while IFS=',' read -r email name department; do
  python3 cs3/scripts/provision_employee.py \
    --user-pool-id $POOL_ID \
    --db-host $DB_HOST \
    --db-name employees \
    --db-user admin \
    --db-password $DB_PASSWORD \
    --email "$email" \
    --name "$name" \
    --department "$department"
done < employees.csv
```

## De-provisioning an Employee

### Manual De-provisioning

Deprovision an employee during offboarding:

```bash
python3 cs3/scripts/deprovision_employee.py \
  --user-pool-id <COGNITO_POOL_ID> \
  --db-host <RDS_ENDPOINT> \
  --db-name employees \
  --db-user admin \
  --db-password <DB_PASSWORD> \
  --email john.doe@innovatech.local
```

The script will:
1. Disable the Cognito user account
2. Remove user from all groups
3. Mark employee as offboarded in database
4. Log the action in the audit table

Output example:
```
Starting de-provisioning for: john.doe@innovatech.local
✓ Disabled Cognito user: john.doe@innovatech.local
  ✓ Removed from group: employees
✓ Marked employee as offboarded: john.doe@innovatech.local

✓ Successfully de-provisioned: john.doe@innovatech.local
```

## GitHub Actions Integration

The provisioning/de-provisioning scripts can be triggered from GitHub Actions:

```yaml
- name: Provision Employee
  run: |
    python3 cs3/scripts/provision_employee.py \
      --user-pool-id ${{ secrets.COGNITO_POOL_ID }} \
      --db-host ${{ secrets.RDS_HOST }} \
      --db-name employees \
      --db-user admin \
      --db-password ${{ secrets.CS3_DB_PASSWORD }} \
      --email ${{ github.event.inputs.email }} \
      --name ${{ github.event.inputs.name }} \
      --department ${{ github.event.inputs.department }}
```

## Security Considerations

1. **Temporary Passwords**: The provisioning script generates a strong 16-character temporary password. Employees must change it on first login.

2. **MFA**: AWS Cognito is configured for optional MFA. Enable it for privileged accounts (HR, Admins).

3. **Password Policy**: Requires uppercase, lowercase, numbers, and symbols (minimum 12 characters).

4. **Audit Trail**: All provisioning/de-provisioning actions are logged to the `employee_audit_log` table with timestamps and operator information.

5. **Database Access**: Passwords should be stored in GitHub Secrets (not Variables) and never committed to the repository.

6. **Group-Based Access**: Use Cognito groups to assign role-based permissions rather than individual IAM policies.

## Troubleshooting

### Error: "User already exists"
The email is already registered in Cognito. Use `aws cognito-idp admin-get-user` to check the account status.

### Error: "Database connection failed"
Verify the RDS security group allows inbound connections on port 5432 from the GitHub Actions runner or execution environment.

### Error: "Missing database record"
The employee table may not have been initialized. Run the schema.sql script:
```bash
psql -h <RDS_HOST> -U admin -d employees -f cs3/terraform/rds/schema.sql
```

## Next Steps (Phase 3)

Phase 3 will add:
- Real portal application code (replace nginx)
- API backend for employee requests
- Logging pipeline (Loki + Fluentd)
- Self-service request workflows
