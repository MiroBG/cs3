#!/usr/bin/env python3
"""
CS3 Employee Self-Service Portal

Flask application for employee lifecycle requests and profile management.
Integrates with Cognito for authentication and PostgreSQL for data.
"""

import os
import json
import logging
import time
import secrets
import string
from datetime import datetime
from functools import wraps
from flask import Flask, render_template, request, jsonify, session, redirect, url_for
import boto3
from botocore.exceptions import ClientError, BotoCoreError
import psycopg2
from psycopg2.extras import RealDictCursor
import requests
from urllib.parse import urlencode

# Logging configuration
logging.basicConfig(
    level=logging.INFO,
    format='{"timestamp": "%(asctime)s", "level": "%(levelname)s", "message": "%(message)s"}',
)
logger = logging.getLogger(__name__)

# Flask app setup
app = Flask(__name__)
app.secret_key = os.getenv("FLASK_SECRET_KEY", "dev-secret-key-change-in-production")

# Configuration
COGNITO_DOMAIN = os.getenv("COGNITO_DOMAIN", "cs3-employees-prod")
COGNITO_CLIENT_ID = os.getenv("COGNITO_CLIENT_ID", "")
COGNITO_CLIENT_SECRET = os.getenv("COGNITO_CLIENT_SECRET", "")
COGNITO_USER_POOL_ID = os.getenv("COGNITO_USER_POOL_ID", "")
COGNITO_REGION = os.getenv("AWS_REGION", "eu-central-1")
PORTAL_URL = os.getenv("PORTAL_URL", "http://localhost:3000")

# Database configuration
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_NAME = os.getenv("DB_NAME", "employees")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")
DB_PORT = int(os.getenv("DB_PORT", 5432))

REQUEST_COUNTS = {}
REQUEST_LATENCY = {}
COGNITO_CLIENT = boto3.client("cognito-idp", region_name=COGNITO_REGION)


def get_db_connection():
    """Get PostgreSQL connection."""
    try:
        return psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            port=DB_PORT,
        )
    except psycopg2.Error as e:
        logger.error(f"Database connection error: {e}")
        return None


def metric_route():
    """Use stable Flask route labels for Prometheus metrics."""
    if request.endpoint and request.url_rule:
        return request.url_rule.rule
    return request.path


@app.before_request
def start_request_timer():
    request._cs3_start_time = time.time()


@app.after_request
def record_request_metrics(response):
    route = metric_route()
    labels = (request.method, route, str(response.status_code))
    REQUEST_COUNTS[labels] = REQUEST_COUNTS.get(labels, 0) + 1

    duration = time.time() - getattr(request, "_cs3_start_time", time.time())
    latency_key = (request.method, route)
    stats = REQUEST_LATENCY.setdefault(latency_key, {"count": 0, "sum": 0.0})
    stats["count"] += 1
    stats["sum"] += duration
    return response


def cognito_configured():
    """Return true when Cognito hosted UI can be used."""
    return all(
        [
            COGNITO_CLIENT_ID,
            COGNITO_CLIENT_SECRET,
            COGNITO_DOMAIN,
            COGNITO_DOMAIN.lower() not in {"disabled", "none", "local"},
        ]
    )


def cognito_login_required(f):
    """Decorator to require Cognito authentication."""

    @wraps(f)
    def decorated_function(*args, **kwargs):
        if "user" not in session:
            return redirect(url_for("login"))
        return f(*args, **kwargs)

    return decorated_function


def get_employee_by_email(email):
    """Return an employee database record for the given email."""
    conn = get_db_connection()
    if not conn:
        return None

    try:
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            "SELECT id, email, name, department, status, role, created_at FROM employees WHERE email = %s",
            (email,),
        )
        employee = cursor.fetchone()
        cursor.close()
        return dict(employee) if employee else None
    except psycopg2.Error as e:
        logger.error(f"Employee lookup failed: {e}")
        return None
    finally:
        conn.close()


def admin_required(f):
    """Require the current portal user to have the admin role in PostgreSQL."""

    @wraps(f)
    def decorated_function(*args, **kwargs):
        email = session.get("user", {}).get("email")
        if not email:
            return jsonify({"error": "No email in session"}), 401

        employee = get_employee_by_email(email)
        if not employee or employee.get("role") != "admin":
            return jsonify({"error": "Admin access required"}), 403

        return f(*args, **kwargs)

    return decorated_function


def generate_temporary_password(length=16):
    """Generate a Cognito-compatible temporary password."""
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
    required = [
        secrets.choice(string.ascii_lowercase),
        secrets.choice(string.ascii_uppercase),
        secrets.choice(string.digits),
        secrets.choice("!@#$%^&*"),
    ]
    remaining = [secrets.choice(alphabet) for _ in range(length - len(required))]
    password_chars = required + remaining
    secrets.SystemRandom().shuffle(password_chars)
    return "".join(password_chars)


def ensure_cognito_group(group_name):
    """Create the Cognito group if it does not already exist."""
    try:
        COGNITO_CLIENT.get_group(UserPoolId=COGNITO_USER_POOL_ID, GroupName=group_name)
    except COGNITO_CLIENT.exceptions.ResourceNotFoundException:
        try:
            COGNITO_CLIENT.create_group(
                UserPoolId=COGNITO_USER_POOL_ID,
                GroupName=group_name,
                Description=f"CS3 {group_name} users",
            )
        except COGNITO_CLIENT.exceptions.GroupExistsException:
            return


def create_cognito_account(email, name, department, role, temporary_password):
    """Create a Cognito user and assign it to a role-matching group."""
    if not COGNITO_USER_POOL_ID:
        raise RuntimeError("COGNITO_USER_POOL_ID is not configured")

    created = False
    try:
        COGNITO_CLIENT.admin_create_user(
            UserPoolId=COGNITO_USER_POOL_ID,
            Username=email,
            UserAttributes=[
                {"Name": "email", "Value": email},
                {"Name": "email_verified", "Value": "true"},
                {"Name": "name", "Value": name},
                {"Name": "custom:department", "Value": department},
                {"Name": "custom:custom_status", "Value": "active"},
            ],
            TemporaryPassword=temporary_password,
            MessageAction="SUPPRESS",
        )
        created = True

        ensure_cognito_group(role)
        COGNITO_CLIENT.admin_add_user_to_group(
            UserPoolId=COGNITO_USER_POOL_ID,
            Username=email,
            GroupName=role,
        )
    except Exception:
        if created:
            try:
                COGNITO_CLIENT.admin_delete_user(UserPoolId=COGNITO_USER_POOL_ID, Username=email)
            except (ClientError, BotoCoreError):
                logger.warning(f"Could not roll back Cognito user {email}")
        raise


@app.route("/")
def index():
    """Portal home page."""
    if "user" in session:
        return redirect(url_for("dashboard"))
    return redirect(url_for("login"))


@app.route("/login")
def login():
    """Cognito login redirect."""
    if not cognito_configured():
        return (
            jsonify(
                {
                    "error": "Cognito hosted UI is not configured",
                    "hint": "Set COGNITO_DOMAIN to the Cognito hosted UI domain.",
                }
            ),
            503,
        )

    params = {
        "client_id": COGNITO_CLIENT_ID,
        "response_type": "code",
        "scope": "openid email profile",
        "redirect_uri": f"{PORTAL_URL}/callback",
        "state": "state-parameter-placeholder",
    }
    auth_url = (
        f"https://{COGNITO_DOMAIN}.auth.{COGNITO_REGION}.amazoncognito.com/oauth2/authorize"
    )
    return redirect(f"{auth_url}?{urlencode(params)}")


@app.route("/callback")
def callback():
    """Cognito OAuth callback."""
    code = request.args.get("code")
    if not code:
        return jsonify({"error": "No authorization code"}), 400

    try:
        # Exchange code for token
        token_url = f"https://{COGNITO_DOMAIN}.auth.{COGNITO_REGION}.amazoncognito.com/oauth2/token"
        token_data = {
            "grant_type": "authorization_code",
            "client_id": COGNITO_CLIENT_ID,
            "client_secret": COGNITO_CLIENT_SECRET,
            "code": code,
            "redirect_uri": f"{PORTAL_URL}/callback",
        }
        response = requests.post(token_url, data=token_data)
        response.raise_for_status()

        tokens = response.json()
        id_token = tokens.get("id_token")

        # Decode JWT (simplified; use PyJWT in production)
        import base64

        parts = id_token.split(".")
        payload = parts[1] + "==="  # Add padding
        decoded = json.loads(base64.urlsafe_b64decode(payload))

        session["user"] = {
            "email": decoded.get("email"),
            "name": decoded.get("name"),
            "sub": decoded.get("sub"),
        }
        logger.info(f"User logged in: {decoded.get('email')}")

        return redirect(url_for("dashboard"))
    except Exception as e:
        logger.error(f"OAuth callback error: {e}")
        return jsonify({"error": "Authentication failed"}), 401


@app.route("/logout")
def logout():
    """Logout and clear session."""
    session.clear()
    if not cognito_configured():
        return redirect(url_for("login"))

    logout_url = f"https://{COGNITO_DOMAIN}.auth.{COGNITO_REGION}.amazoncognito.com/logout"
    params = {"client_id": COGNITO_CLIENT_ID, "logout_uri": PORTAL_URL}
    return redirect(f"{logout_url}?{urlencode(params)}")


@app.route("/dashboard")
@cognito_login_required
def dashboard():
    """Employee dashboard."""
    return render_template(
        "dashboard.html",
        user=session.get("user"),
        portal_url=PORTAL_URL,
    )


@app.route("/api/profile")
@cognito_login_required
def get_profile():
    """Get employee profile from database."""
    email = session.get("user", {}).get("email")
    if not email:
        return jsonify({"error": "No email in session"}), 401

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    cursor = None
    try:
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            "SELECT id, email, name, department, status, role, created_at FROM employees WHERE email = %s",
            (email,),
        )
        profile = cursor.fetchone()

        if not profile:
            return jsonify({"error": "Profile not found"}), 404

        return jsonify(dict(profile))
    except psycopg2.Error as e:
        logger.error(f"Database error: {e}")
        return jsonify({"error": "Database error"}), 500
    finally:
        if cursor:
            cursor.close()
        conn.close()


@app.route("/api/requests", methods=["GET", "POST"])
@cognito_login_required
def manage_requests():
    """Get or create employee requests."""
    email = session.get("user", {}).get("email")
    if not email:
        return jsonify({"error": "No email in session"}), 401

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    cursor = None
    try:
        cursor = conn.cursor(cursor_factory=RealDictCursor)

        if request.method == "GET":
            # Get employee's requests
            cursor.execute(
                "SELECT * FROM employee_requests WHERE email = %s ORDER BY created_at DESC",
                (email,),
            )
            requests_list = cursor.fetchall()
            return jsonify([dict(r) for r in requests_list])

        elif request.method == "POST":
            # Create new request
            data = request.get_json()
            request_type = data.get("type")  # e.g., "equipment", "access", "leave"
            description = data.get("description")

            if not request_type or not description:
                return jsonify({"error": "Missing required fields"}), 400

            cursor.execute(
                """
                INSERT INTO employee_requests (email, request_type, description, status, created_at)
                VALUES (%s, %s, %s, %s, %s)
                RETURNING id, email, request_type, description, status, created_at
                """,
                (email, request_type, description, "pending", datetime.now()),
            )
            new_request = cursor.fetchone()
            conn.commit()
            logger.info(f"Created request for {email}: {request_type}")

            return jsonify(dict(new_request)), 201

    except psycopg2.Error as e:
        conn.rollback()
        logger.error(f"Database error: {e}")
        return jsonify({"error": "Database error"}), 500
    finally:
        if cursor:
            cursor.close()
        conn.close()


@app.route("/api/admin/employees", methods=["POST"])
@cognito_login_required
@admin_required
def provision_employee_account():
    """Provision a Cognito account, group assignment, employee row, and audit entry."""
    if not COGNITO_USER_POOL_ID:
        return jsonify({"error": "Account provisioning unavailable: COGNITO_USER_POOL_ID is not configured"}), 503

    data = request.get_json(silent=True) or {}
    email = (data.get("email") or "").strip().lower()
    name = (data.get("name") or "").strip()
    department = (data.get("department") or "").strip()
    role = (data.get("role") or "employee").strip().lower()
    temporary_password = (data.get("temporary_password") or "").strip()
    performed_by = session.get("user", {}).get("email", "unknown")

    if not email or "@" not in email:
        return jsonify({"error": "A valid email is required"}), 400
    if not name:
        return jsonify({"error": "Name is required"}), 400
    if not department:
        return jsonify({"error": "Department is required"}), 400
    if role not in {"employee", "hr", "admin"}:
        return jsonify({"error": "Role must be employee, hr, or admin"}), 400

    generated_password = False
    if not temporary_password:
        temporary_password = generate_temporary_password()
        generated_password = True

    try:
        create_cognito_account(email, name, department, role, temporary_password)
    except COGNITO_CLIENT.exceptions.UsernameExistsException:
        return jsonify({"error": "Cognito user already exists"}), 409
    except (ClientError, BotoCoreError, RuntimeError) as e:
        logger.error(f"Cognito provisioning failed for {email}: {e}")
        return jsonify({"error": "Cognito provisioning failed", "details": str(e)}), 502

    conn = get_db_connection()
    if not conn:
        try:
            COGNITO_CLIENT.admin_delete_user(UserPoolId=COGNITO_USER_POOL_ID, Username=email)
        except (ClientError, BotoCoreError) as e:
            logger.error(f"Failed to roll back Cognito user {email}: {e}")
        return jsonify({"error": "Database connection failed"}), 500

    cursor = None
    try:
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            """
            INSERT INTO employees (email, name, department, status, role, created_at, updated_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            RETURNING id, email, name, department, status, role, created_at
            """,
            (email, name, department, "active", role, datetime.now(), datetime.now()),
        )
        employee = cursor.fetchone()
        cursor.execute(
            """
            INSERT INTO employee_audit_log (employee_id, action, old_status, new_status, performed_by, timestamp)
            VALUES (%s, %s, %s, %s, %s, %s)
            """,
            (
                employee["id"],
                "provision",
                None,
                "active",
                performed_by,
                datetime.now(),
            ),
        )
        conn.commit()
        logger.info(f"Provisioned employee {email} by {performed_by}")

        response = {
            "employee": dict(employee),
            "cognito_group": role,
            "temporary_password_generated": generated_password,
        }
        if generated_password:
            response["temporary_password"] = temporary_password
        return jsonify(response), 201
    except psycopg2.IntegrityError:
        conn.rollback()
        try:
            COGNITO_CLIENT.admin_delete_user(UserPoolId=COGNITO_USER_POOL_ID, Username=email)
        except (ClientError, BotoCoreError) as e:
            logger.error(f"Failed to roll back duplicate Cognito user {email}: {e}")
        return jsonify({"error": "Employee already exists in PostgreSQL"}), 409
    except psycopg2.Error as e:
        conn.rollback()
        logger.error(f"Database provisioning failed for {email}: {e}")
        try:
            COGNITO_CLIENT.admin_delete_user(UserPoolId=COGNITO_USER_POOL_ID, Username=email)
        except (ClientError, BotoCoreError) as rollback_error:
            logger.error(f"Failed to roll back Cognito user {email}: {rollback_error}")
        return jsonify({"error": "Database provisioning failed"}), 500
    finally:
        if cursor:
            cursor.close()
        conn.close()


@app.route("/api/health")
def health():
    """Health check endpoint for Kubernetes."""
    try:
        conn = get_db_connection()
        if conn:
            conn.close()
            return jsonify({"status": "healthy"}), 200
        return jsonify({"status": "unhealthy", "error": "database connection failed"}), 500
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return jsonify({"status": "unhealthy", "error": str(e)}), 500


@app.route("/metrics")
def metrics():
    """Prometheus metrics endpoint for portal health and API activity."""
    conn = get_db_connection()
    db_up = 1 if conn else 0
    employee_count = 0
    pending_request_count = 0
    if conn:
        try:
            cursor = conn.cursor()
            cursor.execute("SELECT COUNT(*) FROM employees")
            employee_count = cursor.fetchone()[0]
            cursor.execute("SELECT COUNT(*) FROM employee_requests WHERE status = 'pending'")
            pending_request_count = cursor.fetchone()[0]
            cursor.close()
        except psycopg2.Error as e:
            logger.error(f"Metrics database query failed: {e}")
        finally:
            conn.close()

    lines = [
        "# HELP cs3_portal_info CS3 portal application info",
        "# TYPE cs3_portal_info gauge",
        'cs3_portal_info{app="cs3-portal"} 1',
        "# HELP cs3_portal_database_up Database connectivity status",
        "# TYPE cs3_portal_database_up gauge",
        f"cs3_portal_database_up {db_up}",
        "# HELP cs3_portal_employees_total Employee records in the portal database",
        "# TYPE cs3_portal_employees_total gauge",
        f"cs3_portal_employees_total {employee_count}",
        "# HELP cs3_portal_pending_requests_total Pending self-service requests",
        "# TYPE cs3_portal_pending_requests_total gauge",
        f"cs3_portal_pending_requests_total {pending_request_count}",
        "# HELP cs3_portal_http_requests_total HTTP requests handled by the portal",
        "# TYPE cs3_portal_http_requests_total counter",
    ]

    for (method, route, status), count in sorted(REQUEST_COUNTS.items()):
        lines.append(
            f'cs3_portal_http_requests_total{{method="{method}",route="{route}",status="{status}"}} {count}'
        )

    lines.extend(
        [
            "# HELP cs3_portal_request_latency_seconds Request latency by route",
            "# TYPE cs3_portal_request_latency_seconds summary",
        ]
    )
    for (method, route), stats in sorted(REQUEST_LATENCY.items()):
        lines.append(
            f'cs3_portal_request_latency_seconds_count{{method="{method}",route="{route}"}} {stats["count"]}'
        )
        lines.append(
            f'cs3_portal_request_latency_seconds_sum{{method="{method}",route="{route}"}} {stats["sum"]:.6f}'
        )

    body = "\n".join(lines) + "\n"
    return app.response_class(body, mimetype="text/plain")


@app.errorhandler(404)
def not_found(e):
    """Handle 404 errors."""
    return jsonify({"error": "Not found"}), 404


@app.errorhandler(500)
def internal_error(e):
    """Handle 500 errors."""
    logger.error(f"Internal error: {e}")
    return jsonify({"error": "Internal server error"}), 500


if __name__ == "__main__":
    logger.info("Starting CS3 Employee Portal")
    app.run(host="0.0.0.0", port=5000, debug=False)
