#!/usr/bin/env python3
"""
CS3 Employee Self-Service Portal

Flask application for employee lifecycle requests and profile management.
Integrates with Cognito for authentication and PostgreSQL for data.
"""

import os
import json
import logging
from datetime import datetime
from functools import wraps
from flask import Flask, render_template, request, jsonify, session, redirect, url_for
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
COGNITO_REGION = os.getenv("AWS_REGION", "eu-central-1")
PORTAL_URL = os.getenv("PORTAL_URL", "http://localhost:3000")
DEMO_AUTH_ENABLED = os.getenv("PORTAL_DEMO_AUTH", "false").lower() == "true"

# Database configuration
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_NAME = os.getenv("DB_NAME", "employees")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")
DB_PORT = int(os.getenv("DB_PORT", 5432))


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


def start_demo_session():
    """Create a demo session for local/k3s runs without a Cognito domain."""
    session["user"] = {
        "email": "john.doe@innovatech.local",
        "name": "John Doe",
        "sub": "demo-user",
    }
    logger.info("Demo portal session started")
    return redirect(url_for("dashboard"))


def cognito_login_required(f):
    """Decorator to require Cognito authentication."""

    @wraps(f)
    def decorated_function(*args, **kwargs):
        if "user" not in session:
            return redirect(url_for("login"))
        return f(*args, **kwargs)

    return decorated_function


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
        if DEMO_AUTH_ENABLED:
            return start_demo_session()
        return (
            jsonify(
                {
                    "error": "Cognito hosted UI is not configured",
                    "hint": "Set COGNITO_DOMAIN or enable PORTAL_DEMO_AUTH for the k3s demo.",
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

    try:
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            "SELECT id, email, name, department, status, role, created_at FROM employees WHERE email = %s",
            (email,),
        )
        profile = cursor.fetchone()
        cursor.close()
        conn.close()

        if not profile:
            return jsonify({"error": "Profile not found"}), 404

        return jsonify(dict(profile))
    except psycopg2.Error as e:
        logger.error(f"Database error: {e}")
        return jsonify({"error": "Database error"}), 500
    finally:
        if conn:
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
    """Minimal Prometheus metrics endpoint."""
    conn = get_db_connection()
    db_up = 1 if conn else 0
    if conn:
        conn.close()

    body = "\n".join(
        [
            "# HELP cs3_portal_info CS3 portal application info",
            "# TYPE cs3_portal_info gauge",
            'cs3_portal_info{app="cs3-portal"} 1',
            "# HELP cs3_portal_database_up Database connectivity status",
            "# TYPE cs3_portal_database_up gauge",
            f"cs3_portal_database_up {db_up}",
            "",
        ]
    )
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
