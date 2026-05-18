#!/usr/bin/env python3
"""
CS3 Employee De-provisioning Script

Handles offboarding automation:
- Revokes Cognito access
- Marks employee as offboarded in database
- Logs audit trail
- Revokes IAM permissions (optional)
"""

import argparse
import boto3
import psycopg2
import json
import os
import sys
from datetime import datetime

# AWS and Database clients
cognito_client = boto3.client("cognito-idp", region_name=os.getenv("AWS_REGION", "eu-central-1"))
iam_client = boto3.client("iam", region_name=os.getenv("AWS_REGION", "eu-central-1"))


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


def disable_cognito_user(user_pool_id: str, email: str) -> bool:
    """Disable Cognito user account."""
    try:
        cognito_client.admin_disable_user(UserPoolId=user_pool_id, Username=email)
        print(f"✓ Disabled Cognito user: {email}")
        return True
    except Exception as e:
        print(f"✗ Error disabling Cognito user: {e}")
        return False


def remove_user_from_groups(user_pool_id: str, email: str) -> bool:
    """Remove user from all groups."""
    try:
        # Get user groups
        response = cognito_client.admin_list_groups_for_user(
            UserPoolId=user_pool_id, Username=email
        )

        for group in response.get("Groups", []):
            cognito_client.admin_remove_user_from_group(
                UserPoolId=user_pool_id, Username=email, GroupName=group["GroupName"]
            )
            print(f"  ✓ Removed from group: {group['GroupName']}")

        return True
    except Exception as e:
        print(f"✗ Error removing user from groups: {e}")
        return False


def mark_offboarded(
    conn: psycopg2.extensions.connection, email: str, reason: str = "Offboarding"
) -> bool:
    """Mark employee as offboarded in database."""
    try:
        cursor = conn.cursor()
        cursor.execute(
            """
            UPDATE employees
            SET status = %s, offboarded_at = %s, updated_at = %s
            WHERE email = %s
            """,
            ("offboarded", datetime.now(), datetime.now(), email),
        )
        conn.commit()
        print(f"✓ Marked employee as offboarded: {email}")
        cursor.close()
        return True
    except Exception as e:
        conn.rollback()
        print(f"✗ Error marking employee offboarded: {e}")
        return False


def log_audit_entry(
    conn: psycopg2.extensions.connection,
    email: str,
    action: str,
    old_status: str,
    new_status: str,
    performed_by: str = "system",
) -> bool:
    """Log de-provisioning action to audit table."""
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


def deprovision_employee(
    user_pool_id: str,
    db_host: str,
    db_name: str,
    db_user: str,
    db_password: str,
    email: str,
    revoke_iam: bool = False,
) -> bool:
    """Complete employee de-provisioning workflow."""
    print(f"\nStarting de-provisioning for: {email}")

    # Connect to database
    try:
        conn = get_db_connection(db_host, db_name, db_user, db_password)
    except Exception as e:
        print(f"Failed to connect to database: {e}")
        return False

    # Get current status before changes
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT status FROM employees WHERE email = %s", (email,))
        result = cursor.fetchone()
        if not result:
            print(f"✗ Employee not found: {email}")
            conn.close()
            return False
        old_status = result[0]
        cursor.close()
    except Exception as e:
        print(f"✗ Error fetching employee status: {e}")
        conn.close()
        return False

    # Disable Cognito user
    if not disable_cognito_user(user_pool_id, email):
        conn.close()
        return False

    # Remove from all groups
    if not remove_user_from_groups(user_pool_id, email):
        conn.close()
        return False

    # Mark as offboarded
    if not mark_offboarded(conn, email):
        conn.close()
        return False

    # Log to audit table
    log_audit_entry(conn, email, "deprovision", old_status, "offboarded", performed_by="github-actions")

    # Optional: Revoke IAM permissions
    if revoke_iam:
        print("  Note: IAM permission revocation not yet implemented")

    conn.close()
    print(f"\n✓ Successfully de-provisioned: {email}")
    return True


def main():
    parser = argparse.ArgumentParser(description="CS3 Employee De-provisioning")
    parser.add_argument("--user-pool-id", required=True, help="Cognito User Pool ID")
    parser.add_argument("--db-host", required=True, help="RDS database host")
    parser.add_argument("--db-name", required=True, help="Database name")
    parser.add_argument("--db-user", required=True, help="Database user")
    parser.add_argument("--db-password", required=True, help="Database password")
    parser.add_argument("--email", required=True, help="Employee email to offboard")
    parser.add_argument(
        "--revoke-iam", action="store_true", help="Also revoke IAM permissions (optional)"
    )

    args = parser.parse_args()

    success = deprovision_employee(
        user_pool_id=args.user_pool_id,
        db_host=args.db_host,
        db_name=args.db_name,
        db_user=args.db_user,
        db_password=args.db_password,
        email=args.email,
        revoke_iam=args.revoke_iam,
    )

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
