# Phase 4: Security, Testing & Operations

## Goal
Complete security hardening, automated testing, monitoring dashboards, and operational runbooks so the CS3 stack is production-ready and auditable.

## High-level plan
1. Threat modeling & security specification
2. Implement network policies and pod isolation
3. Enforce RBAC and least-privilege IAM for AWS
4. Add WAF/ingress protection for the portal
5. Secrets management and secret rotation
6. Container supply-chain hardening (image signing, scanning)
7. IaC and cluster security scanning (tfsec, checkov, kube-bench)
8. Integration tests and automated test harness
9. Monitoring dashboards, alerts, and SLOs
10. Operational runbooks and incident response playbooks

---

## 1) Threat modeling & security spec (first deliverable)
- Identify assets: RDS (employee data), Cognito (identity), EKS (portal), ECR (images), S3 (documents)
- Enumerate threats: unauthorized access, privilege escalation, data exfiltration, supply-chain compromise, misconfigurations
- Define security controls: network segmentation, RBAC, MFA enforcement, encryption in transit & at rest, WAF, rate limiting
- Deliverables: `threat_model.md`, `security_requirements.md` (C-I-A + retention/compliance), prioritized backlog of fixes

## 2) Network policies & pod isolation
- Implement `NetworkPolicy` to deny-by-default then allow minimal ingress/egress
- Isolate namespaces: `portal`, `logging`, `kube-system`, `db-admin`
- Use SecurityContext to enforce non-root containers and read-only root FS
- Deliverables: `k8s/networkpolicies/` manifests and Terraform helm/helm_release to enforce (if using Calico/Policy engine)

## 3) RBAC and IAM least-privilege
- Create Kubernetes RBAC roles for portal operators and CI/CD service accounts
- Restrict AWS IAM roles: least privilege for GitHub Actions, EKS node role (ECR pull only), RDS access via IAM where possible
- Deliverables: `terraform/iam/` policy documents and Kubernetes `Role`/`RoleBinding` manifests

## 4) WAF & Ingress protection
- Deploy AWS WAF on ALB (or CloudFront) with OWASP rules and custom rules
- Rate-limit endpoints and protect login/callback endpoints
- Deliverables: Terraform `aws_wafv2_web_acl` for portal ALB, integration tests for blocked requests

## 5) Secrets management
- Move sensitive values to AWS Secrets Manager or SSM Parameter Store and reference in Terraform
- Implement automatic rotation for DB credentials and Cognito client secrets where possible
- Deliverables: `terraform/secrets/` module and small scripts to rotate/test secrets

## 6) Container supply-chain hardening
- Add Trivy scan and policy gating to GitHub Actions
- Consider image signing (cosign) and enforce Signed Images in cluster admission (via Sigstore + OPA/Gatekeeper)
- Deliverables: GitHub Actions `security` job, cosign keys, admission controller policy examples

## 7) IaC and cluster security scanning
- Add `tfsec` and `checkov` scans to CI
- Run `kube-bench` and `kube-hunter` periodically or in pre-deploy checks
- Deliverables: `.github/workflows/cs3_security.yml`, baseline reports in artifacts

## 8) Integration & security tests
- Implement end-to-end tests for portal login, request creation, DB persistence
- Add smoke tests for health endpoints and RBAC enforcement
- Deliverables: `tests/` using pytest + requests, GitHub Actions job for running tests

## 9) Monitoring, dashboards & alerts
- Create Grafana dashboards for application latency, error rates, DB connections, auth failures
- Add alerting rules (PagerDuty/Slack) for high-error rates and failed deployments
- Deliverables: `grafana/provisioning/` dashboards and alert rules, Terraform alert channels

## 10) Runbooks & incident response
- Create runbooks for: failed deploy, DB compromise, token leakage, high-latency incidents
- Define escalation path and on-call rotations (if available)
- Deliverables: `runbooks/` markdown files, playbooks for common incidents

---

## Immediate next actions (first sprint)
1. Create `threat_model.md` and `security_requirements.md` (deliverable in repo)
2. Add GitHub Actions security workflow (`.github/workflows/cs3_security.yml`) to run `tfsec`, `trivy`, `kube-bench` (scans only)
3. Create initial `k8s/networkpolicies/` manifest that implements deny-by-default and allows necessary portal traffic (non-destructive)

I will implement steps 1–3 now: add the threat model draft, the security CI workflow, and a conservative network policy manifest.