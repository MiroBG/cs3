from pathlib import Path


def read(path: str) -> str:
    return Path(__file__).resolve().parents[1].joinpath(path).read_text()


def test_portal_deployment_uses_flask_port():
    content = read("k8s/portal/deployment.yaml")
    assert "containerPort: 5000" in content
    assert "readinessProbe" in content
    assert "livenessProbe" in content
    assert "PORTAL_ECR_IMAGE" in content


def test_portal_service_exposes_load_balancer():
    content = read("k8s/portal/service.yaml")
    assert "type: LoadBalancer" in content
    assert "targetPort: 5000" in content
    assert "kind: NetworkPolicy" in content


def test_network_policies_are_deny_by_default():
    content = read("k8s/networkpolicies/deny-by-default.yaml")
    assert "deny-by-default" in content
    assert "policyTypes:" in content
    assert "Ingress" in content
    assert "Egress" in content
