# Security Requirements — CS3

## Goals
- Protect confidentiality, integrity, and availability of employee data
- Ensure secure and auditable onboarding/offboarding flows
- Harden CI/CD and supply chain to prevent unauthorized changes
- Provide monitoring, alerting, and runbooks for incident response

## Requirements (MUST)
- All secrets stored in AWS Secrets Manager; no plaintext secrets in repo
- Terraform state stored in S3 with encryption + DynamoDB locks
- EKS nodes must run non-root containers and use read-only root FS where possible
- Network policies: deny-by-default; only allow necessary traffic between namespaces
- RBAC: least-privilege roles for humans and service accounts
- GitHub Actions: OIDC role with least-privilege policies, require MFA for admin actions
- Container images: must pass Trivy high/critical checks and be cosign-signed
- IaC scanning: `tfsec` and `checkov` on PRs; fail PRs on high-severity findings
- WAF: OWASP managed rules applied to portal ALB/CloudFront
- Logging: 7-day retention, alerts on anomalous login failures and high error rates

## Requirements (SHOULD)
- Automatic rotation of DB credentials (Secrets Manager rotation)
- Admission controller enforcing signed images and approved registries
- Periodic `kube-bench` and `kube-hunter` reports
- Automated integration tests for critical user journeys

## Acceptance Criteria
- CI pipeline runs `tfsec`, `checkov`, `trivy` and produces artifacts
- At least one NetworkPolicy exists enforcing deny-by-default and portal ingress
- Secrets Manager contains DB password and Cognito client secret, referenced by Terraform
- RBAC roles created for portal operators with least privilege
- A WAF web ACL Terraform stub exists ready for configuration

