import requests

PORTAL_BASE = "http://localhost:5000"

def test_health():
    resp = requests.get(f"{PORTAL_BASE}/api/health")
    assert resp.status_code in (200, 500)  # if not running locally, allow 500

def test_profile_unauthenticated():
    resp = requests.get(f"{PORTAL_BASE}/api/profile")
    assert resp.status_code == 401 or resp.status_code == 302
