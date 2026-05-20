import importlib.util
from pathlib import Path
from types import SimpleNamespace

import pytest


MODULE_PATH = Path(__file__).resolve().parents[1] / "scripts" / "deprovision_employee.py"


@pytest.fixture()
def deprovision_module(monkeypatch):
    fake_cognito = SimpleNamespace(
        admin_disable_user=lambda **kwargs: None,
        admin_list_groups_for_user=lambda **kwargs: {"Groups": [{"GroupName": "employees"}, {"GroupName": "hr"}]},
        admin_remove_user_from_group=lambda **kwargs: None,
    )
    fake_iam = SimpleNamespace()
    fake_psycopg2 = SimpleNamespace(connect=lambda **kwargs: None)

    monkeypatch.setattr("boto3.client", lambda service_name, region_name=None: fake_cognito if service_name == "cognito-idp" else fake_iam)
    monkeypatch.setattr("psycopg2.connect", lambda **kwargs: None)

    spec = importlib.util.spec_from_file_location("deprovision_employee", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class DummyCursor:
    def __init__(self, row):
        self.row = row
        self.queries = []

    def execute(self, query, params=None):
        self.queries.append((query, params))

    def fetchone(self):
        return self.row

    def close(self):
        pass


class DummyConnection:
    def __init__(self, row):
        self.cursor_obj = DummyCursor(row)
        self.commits = 0
        self.rollbacks = 0
        self.closed = False

    def cursor(self):
        return self.cursor_obj

    def commit(self):
        self.commits += 1

    def rollback(self):
        self.rollbacks += 1

    def close(self):
        self.closed = True


def test_deprovision_employee_happy_path(monkeypatch, deprovision_module):
    events = []
    conn = DummyConnection(("active",))

    monkeypatch.setattr(deprovision_module, "get_db_connection", lambda *args, **kwargs: conn)
    monkeypatch.setattr(deprovision_module, "disable_cognito_user", lambda user_pool_id, email: events.append(("disable", user_pool_id, email)) or True)
    monkeypatch.setattr(deprovision_module, "remove_user_from_groups", lambda user_pool_id, email: events.append(("groups", user_pool_id, email)) or True)
    monkeypatch.setattr(deprovision_module, "mark_offboarded", lambda conn, email: events.append(("offboard", email)) or True)
    monkeypatch.setattr(deprovision_module, "log_audit_entry", lambda *args, **kwargs: events.append(("audit", kwargs.get("action"))) or True)

    assert deprovision_module.deprovision_employee(
        user_pool_id="pool",
        db_host="host",
        db_name="db",
        db_user="user",
        db_password="pass",
        email="person@example.com",
        revoke_iam=False,
    ) is True

    assert [e[0] for e in events] == ["disable", "groups", "offboard", "audit"]
    assert conn.closed is True


def test_deprovision_employee_missing_user(monkeypatch, deprovision_module):
    conn = DummyConnection(None)

    monkeypatch.setattr(deprovision_module, "get_db_connection", lambda *args, **kwargs: conn)

    assert deprovision_module.deprovision_employee(
        user_pool_id="pool",
        db_host="host",
        db_name="db",
        db_user="user",
        db_password="pass",
        email="missing@example.com",
        revoke_iam=False,
    ) is False
    assert conn.closed is True
