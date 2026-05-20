#!/usr/bin/env python3
"""
CS3 Employee De-provisioning Script

Handles offboarding automation:
- Revokes Cognito access
- Marks employee as offboarded in database
- Logs audit trail
- Revokes IAM permissions and deletes matching IAM user (optional)
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


def delete_iam_user(iam_username: str) -> bool:
    """Delete an IAM user after removing attached resources.

    The function is intentionally defensive: it removes access keys, login
    profile, inline policies, and attached managed policies before deleting the
    user. If the user does not exist, the cleanup is treated as complete.
    """
    try:
        # Remove access keys
        response = iam_client.list_access_keys(UserName=iam_username)
        for access_key in response.get("AccessKeyMetadata", []):
            iam_client.delete_access_key(
                UserName=iam_username,
                AccessKeyId=access_key["AccessKeyId"],
            )

        # Remove login profile if present
        try:
            iam_client.delete_login_profile(UserName=iam_username)
        except Exception:
            pass

        # Remove inline policies
        inline_policies = iam_client.list_user_policies(UserName=iam_username)
        for policy_name in inline_policies.get("PolicyNames", []):
            iam_client.delete_user_policy(UserName=iam_username, PolicyName=policy_name)

        # Detach managed policies
        attached_policies = iam_client.list_attached_user_policies(UserName=iam_username)
        for policy in attached_policies.get("AttachedPolicies", []):
            iam_client.detach_user_policy(
                UserName=iam_username,
                PolicyArn=policy["PolicyArn"],
            )

        iam_client.delete_user(UserName=iam_username)
        print(f"  ✓ Deleted IAM user: {iam_username}")
        return True
    except iam_client.exceptions.NoSuchEntityException:
        print(f"  ℹ IAM user not found, skipping delete: {iam_username}")
        return True
    except Exception as e:
        print(f"✗ Error deleting IAM user {iam_username}: {e}")
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
    iam_username: str | None = None,
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
        resolved_iam_username = iam_username or email.split("@", 1)[0]
        if not delete_iam_user(resolved_iam_username):
            conn.close()
            return False

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
    parser.add_argument(
        "--iam-username",
        help="Optional IAM username to delete; defaults to the email local-part",
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
        iam_username=args.iam_username,
    )

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
