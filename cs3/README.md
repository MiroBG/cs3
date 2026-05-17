CS3 - Employee Lifecycle & Hybrid Self-Service Portal

This folder contains starter scaffolding for Case Study 3.

Structure:
- terraform/vpc: minimal VPC module scaffold
- terraform/eks: minimal EKS scaffold (placeholder)
- k8s/portal: sample Kubernetes Deployment and Service for the portal
- .github/workflows/cs3_deploy.yml: CI/CD pipeline skeleton

Next steps:
- Flesh out Terraform modules (add NAT Gateway, IGW, route tables, multi-AZ subnets)
- Replace EKS placeholders with the official EKS module or aws_eks_cluster
- Add Helm chart or real container image for the portal
- Wire GitHub Actions with OIDC and add `terraform plan`/`apply` steps

Cost note:
- EKS is the managed Kubernetes option on AWS, but it is not free; the control plane has a fixed cost.
- This scaffold keeps the cluster small by default: one node group, one NAT gateway, and modest instance sizes.
- If the budget becomes the main constraint, a self-managed k3s cluster on EC2 is cheaper but adds more admin work.

Reference: see docs/cs3_requirement_analysis.typ and docs/cs3_design_implementation.typ for design decisions and rationale.
