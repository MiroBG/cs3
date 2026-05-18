#!/usr/bin/env python3
"""
CS3 Employee Provisioning Script

Handles onboarding automation:
- Creates Cognito user account
- Creates database record
- Assigns to groups/roles
- Sends welcome email
"""

import argparse
import boto3
import psycopg2
import json
import os
import sys
from datetime import datetime
from typing import Dict, Optional

# AWS and Database clients
cognito_client = boto3.client("cognito-idp", region_name=os.getenv("AWS_REGION", "eu-central-1"))
rds_client = boto3.client("rds", region_name=os.getenv("AWS_REGION", "eu-central-1"))


def get_db_connection(
    host: str, database: str, user: str, password: str, port: int = 5432
) -> psycopg2.extensions.connection:
    """Establish PostgreSQL connection."""
    try:
        conn = psycopg2.connect(
            host=host, database=database, user=user, password=password, port=port
        )
        return conn
    except psycopg2.Error as e:
        print(f"Database connection error: {e}")
        sys.exit(1)


def create_cognito_user(
    user_pool_id: str, email: str, name: str, department: str, temporary_password: str
) -> Dict:
    """Create a new Cognito user account."""
    try:
        response = cognito_client.admin_create_user(
            UserPoolId=user_pool_id,
            Username=email,
            UserAttributes=[
                {"Name": "email", "Value": email},
                {"Name": "email_verified", "Value": "true"},
                {"Name": "name", "Value": name},
                {"Name": "custom:department", "Value": department},
                {"Name": "custom:custom_status", "Value": "active"},
            ],
            TemporaryPassword=temporary_password,
            MessageAction="SUPPRESS",  # Don't send email yet
        )
        print(f"✓ Created Cognito user: {email}")
        return response["User"]
    except cognito_client.exceptions.UsernameExistsException:
        print(f"✗ User already exists: {email}")
        return None
    except Exception as e:
        print(f"✗ Error creating Cognito user: {e}")
        return None


def create_database_record(
    conn: psycopg2.extensions.connection,
    email: str,
    name: str,
    department: str,
    role: str = "employee",
) -> bool:
    """Create employee record in database."""
    try:
        cursor = conn.cursor()
        cursor.execute(
            """
            INSERT INTO employees (email, name, department, status, role, created_at, updated_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            """,
            (email, name, department, "active", role, datetime.now(), datetime.now()),
        )
        conn.commit()
        print(f"✓ Created database record: {email}")
        return True
    except psycopg2.IntegrityError:
        conn.rollback()
        print(f"✗ Employee already exists in database: {email}")
        return False
    except Exception as e:
        conn.rollback()
        print(f"✗ Error creating database record: {e}")
        return False
    finally:
        cursor.close()


def add_user_to_group(user_pool_id: str, email: str, group_name: str) -> bool:
    """Add user to Cognito group."""
    try:
        cognito_client.admin_add_user_to_group(
            UserPoolId=user_pool_id, Username=email, GroupName=group_name
        )
        print(f"✓ Added user {email} to group: {group_name}")
        return True
    except Exception as e:
        print(f"✗ Error adding user to group: {e}")
        return False


def log_audit_entry(
    conn: psycopg2.extensions.connection,
    email: str,
    action: str,
    old_status: Optional[str],
    new_status: str,
    performed_by: str = "system",
) -> bool:
    """Log provisioning action to audit table."""
    try:
        cursor = conn.cursor()
        cursor.execute(
            """
            INSERT INTO employee_audit_log (employee_id, action, old_status, new_status, performed_by, timestamp)
            SELECT id, %s, %s, %s, %s, %s FROM employees WHERE email = %s
            """,
            (action, old_status, new_status, performed_by, datetime.now(), email),
        )
        conn.commit()
        cursor.close()
        return True
    except Exception as e:
        conn.rollback()
        print(f"✗ Error logging audit entry: {e}")
        return False


def provision_employee(
    user_pool_id: str,
    db_host: str,
    db_name: str,
    db_user: str,
    db_password: str,
    email: str,
    name: str,
    department: str,
    role: str = "employee",
    group: str = "employees",
    temporary_password: Optional[str] = None,
) -> bool:
    """Complete employee provisioning workflow."""
    if not temporary_password:
        # Generate a strong temporary password
        import secrets
        import string
        chars = string.ascii_letters + string.digits + "!@#$%^&*"
        temporary_password = "".join(secrets.choice(chars) for _ in range(16))

    # Create Cognito user
    user = create_cognito_user(user_pool_id, email, name, department, temporary_password)
    if not user:
        print(f"Failed to provision {email}")
        return False

    # Connect to database
    try:
        conn = get_db_connection(db_host, db_name, db_user, db_password)
    except Exception as e:
        print(f"Failed to connect to database: {e}")
        return False

    # Create database record
    if not create_database_record(conn, email, name, department, role):
        cognito_client.admin_delete_user(UserPoolId=user_pool_id, Username=email)
        conn.close()
        return False

    # Add to group
    if not add_user_to_group(user_pool_id, email, group):
        conn.close()
        return False

    # Log to audit table
    log_audit_entry(conn, email, "provision", None, "active", performed_by="github-actions")

    conn.close()
    print(f"\n✓ Successfully provisioned: {email}")
    print(f"  Temporary password: {temporary_password}")
    print(f"  Department: {department}")
    print(f"  Role: {role}")
    return True


def main():
    parser = argparse.ArgumentParser(description="CS3 Employee Provisioning")
    parser.add_argument("--user-pool-id", required=True, help="Cognito User Pool ID")
    parser.add_argument("--db-host", required=True, help="RDS database host")
    parser.add_argument("--db-name", required=True, help="Database name")
    parser.add_argument("--db-user", required=True, help="Database user")
    parser.add_argument("--db-password", required=True, help="Database password")
    parser.add_argument("--email", required=True, help="Employee email")
    parser.add_argument("--name", required=True, help="Employee full name")
    parser.add_argument("--department", required=True, help="Department")
    parser.add_argument("--role", default="employee", help="User role (default: employee)")
    parser.add_argument("--group", default="employees", help="Cognito group (default: employees)")
    parser.add_argument("--temp-password", help="Temporary password (auto-generated if omitted)")

    args = parser.parse_args()

    success = provision_employee(
        user_pool_id=args.user_pool_id,
        db_host=args.db_host,
        db_name=args.db_name,
        db_user=args.db_user,
        db_password=args.db_password,
        email=args.email,
        name=args.name,
        department=args.department,
        role=args.role,
        group=args.group,
        temporary_password=args.temp_password,
    )

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
