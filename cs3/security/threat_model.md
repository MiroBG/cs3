# Threat Model — CS3 Employee Lifecycle System

## Assets
- RDS PostgreSQL (employee data)
- AWS Cognito (identity provider, tokens)
- EKS cluster (portal + logging)
- ECR (container images)
- S3 (employee documents)
- GitHub repository (CI/CD) and GitHub Actions OIDC role
- Secrets and keys (DB password, Cognito client secret, cosign keys)

## Actors
- Legitimate users (employees, HR, admins)
- Malicious external actors
- Compromised CI/CD (GitHub Actions) runner
- Malicious insider
- Third-party dependencies (images, upstream libraries)

## Threats (Top Risks)
1. Unauthorized data access (exfiltration of PII) — high impact
2. Privilege escalation across Kubernetes cluster — high impact
3. Compromised CI/CD pipeline pushing malicious images — high impact
4. Misconfigured infrastructure leading to public exposure (RDS open) — high impact
5. Secrets leakage (DB password, Cognito client secret) — high impact
6. Supply-chain compromise (malicious npm/pip packages or container image) — medium-high
7. DDoS or abuse of portal authentication endpoints — medium
8. Log injection or sensitive data stored in logs — medium

## Mitigations (Mapping to Controls)
- Network segmentation: deny-by-default NetworkPolicy, separate namespaces for portal and logging
- Least-privilege IAM: minimal GitHub Actions role, EKS node role limited to ECR pull and SSM if needed
- Secrets management: AWS Secrets Manager + automatic rotation for DB credentials
- Image assurance: Trivy scanning + cosign signing and admission policy to require signed images
- IaC scanning: tfsec/checkov in CI to catch misconfiguration early
- WAF: AWS WAF on ALB/CloudFront protecting login endpoints and rate limiting
- Logging & monitoring: Loki/Grafana alerts for suspicious patterns, monitor failed logins and error spikes
- Audit: enable RDS logging, EKS audit logs, CloudTrail for API calls

## Attack Scenarios and Responses
- If RDS is reachable from internet: Immediate action — revoke public access, rotate credentials, inspect recent access, restore from snapshot if required.
- If GitHub OIDC role is misused: Revoke role trust, rotate keys, and audit login tokens; require PR approval and signed commits for critical branches.
- If image scan fails (critical): Block deployment, mark image as unsafe, require remediation and re-scan.

## Next Steps
- Formalize security requirements document (`security/security_requirements.md`)
- Implement automated secrets provisioning and rotation
- Implement cosign signing workflow and admission control (OPA/Gatekeeper)
- Create runbooks for the top attack scenarios
