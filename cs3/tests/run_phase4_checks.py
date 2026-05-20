#!/usr/bin/env python3
"""Phase 4 verification harness without external test dependencies.

Checks:
- Cognito rollback deletion path in provisioning
- Offboarding/deprovision flow
- Kubernetes manifest structure
"""

from __future__ import annotations

import importlib.util
import sys
import types
from pathlib import Path
from typing import Any

import yaml

ROOT = Path(__file__).resolve().parents[1]


class DummyCursor:
    def __init__(self, row=None):
        self.row = row
        self.executed = []
        self.closed = False

    def execute(self, query: str, params: Any = None) -> None:
        self.executed.append((query, params))

    def fetchone(self):
        return self.row

    def close(self) -> None:
        self.closed = True


class DummyConnection:
    def __init__(self, row=None):
        self.row = row
        self.cursor_obj = DummyCursor(row)
        self.closed = False
        self.commits = 0
        self.rollbacks = 0

    def cursor(self):
        return self.cursor_obj

    def commit(self):
        self.commits += 1

    def rollback(self):
        self.rollbacks += 1

    def close(self):
        self.closed = True


class FakeCognitoClient:
    def __init__(self):
        self.calls = []

        class _Exceptions:
            class UsernameExistsException(Exception):
                pass

        self.exceptions = _Exceptions()

    def admin_create_user(self, **kwargs):
        self.calls.append(("admin_create_user", kwargs))
        return {"User": {"Username": kwargs["Username"]}}

    def admin_add_user_to_group(self, **kwargs):
        self.calls.append(("admin_add_user_to_group", kwargs))

    def admin_delete_user(self, **kwargs):
        self.calls.append(("admin_delete_user", kwargs))

    def admin_disable_user(self, **kwargs):
        self.calls.append(("admin_disable_user", kwargs))

    def admin_list_groups_for_user(self, **kwargs):
        self.calls.append(("admin_list_groups_for_user", kwargs))
        return {"Groups": [{"GroupName": "employees"}, {"GroupName": "hr"}]}

    def admin_remove_user_from_group(self, **kwargs):
        self.calls.append(("admin_remove_user_from_group", kwargs))


class FakeIAMClient:
    def __init__(self):
        self.calls = []

        class _Exceptions:
            class NoSuchEntityException(Exception):
                pass

        self.exceptions = _Exceptions()

    def list_access_keys(self, **kwargs):
        self.calls.append(("list_access_keys", kwargs))
        return {"AccessKeyMetadata": [{"AccessKeyId": "AKIA123"}]}

    def delete_access_key(self, **kwargs):
        self.calls.append(("delete_access_key", kwargs))

    def delete_login_profile(self, **kwargs):
        self.calls.append(("delete_login_profile", kwargs))

    def list_user_policies(self, **kwargs):
        self.calls.append(("list_user_policies", kwargs))
        return {"PolicyNames": ["inline-policy"]}

    def delete_user_policy(self, **kwargs):
        self.calls.append(("delete_user_policy", kwargs))

    def list_attached_user_policies(self, **kwargs):
        self.calls.append(("list_attached_user_policies", kwargs))
        return {"AttachedPolicies": [{"PolicyArn": "arn:aws:iam::aws:policy/ReadOnlyAccess"}]}

    def detach_user_policy(self, **kwargs):
        self.calls.append(("detach_user_policy", kwargs))

    def delete_user(self, **kwargs):
        self.calls.append(("delete_user", kwargs))


def install_fakes() -> FakeCognitoClient:
    fake_cognito = FakeCognitoClient()
    fake_boto3 = types.ModuleType("boto3")
    fake_boto3.client = lambda service_name, region_name=None: fake_cognito if service_name == "cognito-idp" else FakeIAMClient()

    fake_psycopg2 = types.ModuleType("psycopg2")
    fake_psycopg2.IntegrityError = type("IntegrityError", (Exception,), {})
    fake_psycopg2.Error = Exception
    fake_psycopg2.connect = lambda **kwargs: DummyConnection()
    fake_psycopg2_extensions = types.ModuleType("psycopg2.extensions")
    fake_psycopg2_extensions.connection = DummyConnection
    fake_psycopg2.extensions = fake_psycopg2_extensions

    sys.modules["boto3"] = fake_boto3
    sys.modules["psycopg2"] = fake_psycopg2
    sys.modules["psycopg2.extensions"] = fake_psycopg2_extensions
    return fake_cognito


def load_module(module_name: str, path: Path):
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


def test_provision_rollback(fake_cognito):
    module = load_module("provision_employee", ROOT / "scripts" / "provision_employee.py")
    conn = DummyConnection()
    deleted = []

    module.get_db_connection = lambda *args, **kwargs: conn
    module.create_database_record = lambda *args, **kwargs: False
    module.cognito_client.admin_delete_user = lambda **kwargs: deleted.append(kwargs)

    ok = module.provision_employee(
        user_pool_id="pool",
        db_host="host",
        db_name="db",
        db_user="user",
        db_password="pass",
        email="alice@example.com",
        name="Alice",
        department="Engineering",
        role="employee",
        group="employees",
        temporary_password="TempPass123!",
    )
    assert ok is False
    assert deleted and deleted[0]["Username"] == "alice@example.com"


def test_deprovision_flow(fake_cognito):
    module = load_module("deprovision_employee", ROOT / "scripts" / "deprovision_employee.py")
    conn = DummyConnection(("active",))
    events = []

    module.get_db_connection = lambda *args, **kwargs: conn
    module.disable_cognito_user = lambda user_pool_id, email: events.append(("disable", user_pool_id, email)) or True
    module.remove_user_from_groups = lambda user_pool_id, email: events.append(("groups", user_pool_id, email)) or True
    module.mark_offboarded = lambda conn, email, reason="Offboarding": events.append(("offboard", email)) or True
    module.log_audit_entry = lambda *args, **kwargs: events.append(("audit", kwargs.get("action"))) or True

    ok = module.deprovision_employee(
        user_pool_id="pool",
        db_host="host",
        db_name="db",
        db_user="user",
        db_password="pass",
        email="bob@example.com",
        revoke_iam=False,
    )
    assert ok is True
    assert [e[0] for e in events] == ["disable", "groups", "offboard", "audit"]
    assert conn.closed is True


def test_iam_user_cleanup(fake_cognito):
    module = load_module("deprovision_employee", ROOT / "scripts" / "deprovision_employee.py")
    fake_iam = FakeIAMClient()
    module.iam_client = fake_iam

    assert module.delete_iam_user("alice") is True
    assert any(call[0] == "delete_user" for call in fake_iam.calls)
    assert any(call[0] == "delete_access_key" for call in fake_iam.calls)
    assert any(call[0] == "detach_user_policy" for call in fake_iam.calls)


def test_kubernetes_manifests():
    deployment = (ROOT / "k8s" / "portal" / "deployment.yaml").read_text()
    service = (ROOT / "k8s" / "portal" / "service.yaml").read_text()
    policies = (ROOT / "k8s" / "networkpolicies" / "deny-by-default.yaml").read_text()

    list(yaml.safe_load_all(deployment))
    list(yaml.safe_load_all(service))
    list(yaml.safe_load_all(policies))

    assert "containerPort: 5000" in deployment
    assert "readinessProbe" in deployment
    assert "livenessProbe" in deployment
    assert "type: LoadBalancer" in service
    assert "targetPort: 5000" in service
    assert "deny-by-default" in policies
    assert "policyTypes:" in policies


def main() -> int:
    fake_cognito = install_fakes()

    failures = []
    for name, fn in [
        ("provision_rollback", lambda: test_provision_rollback(fake_cognito)),
        ("deprovision_flow", lambda: test_deprovision_flow(fake_cognito)),
        ("iam_user_cleanup", lambda: test_iam_user_cleanup(fake_cognito)),
        ("kubernetes_manifests", test_kubernetes_manifests),
    ]:
        try:
            fn()
            print(f"PASS: {name}")
        except Exception as exc:
            failures.append((name, exc))
            print(f"FAIL: {name}: {exc}")

    if failures:
        print("\nSummary: failed checks detected")
        return 1

    print("\nSummary: all Phase 4 checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
