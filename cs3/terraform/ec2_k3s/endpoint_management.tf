# Endpoint / device management (Zero Trust "device" pillar).
#
# This architecture has no end-user laptops; the managed endpoint is the EC2
# compute node, already enrolled via the SSM Agent (AmazonSSMManagedInstanceCore
# is attached to the instance role). SSM State Manager is used as the endpoint
# management plane the same way real orgs manage server fleets:
#   - enrollment        -> the association targets any instance tagged Project=cs3
#   - baseline config   -> the SSM document hardens the host on enroll + on schedule
#   - patch policy       -> AWS-RunPatchBaseline reports patch compliance (Scan)
#
# All resources are gated on enable_endpoint_management so the feature can be
# turned off without touching the rest of the stack.

locals {
  endpoint_mgmt_enabled = var.create_instance && var.enable_endpoint_management ? 1 : 0
}

# Baseline security configuration pushed to managed endpoints.
resource "aws_ssm_document" "endpoint_baseline" {
  count           = local.endpoint_mgmt_enabled
  name            = "${var.name_prefix}-endpoint-baseline${var.resource_suffix_part}"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "CS3 endpoint baseline: patches, SSH hardening, host IDS, audit logging."
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "applyBaseline"
        inputs = {
          timeoutSeconds = "600"
          runCommand = [
            "set -euo pipefail",
            "export DEBIAN_FRONTEND=noninteractive",
            "# Automatic security updates (application/patch deployment policy)",
            "apt-get update -y",
            "apt-get install -y unattended-upgrades fail2ban auditd",
            "dpkg-reconfigure -f noninteractive unattended-upgrades || true",
            "systemctl enable --now unattended-upgrades || true",
            "# Host intrusion prevention + audit logging",
            "systemctl enable --now fail2ban || true",
            "systemctl enable --now auditd || true",
            "# SSH hardening: no password auth, no direct root login",
            "sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config",
            "sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config",
            "sshd -t && systemctl reload ssh || systemctl reload sshd || true",
            "# Note: network filtering is enforced by the EC2 security group; ufw is",
            "# intentionally NOT enabled because it interferes with k3s pod networking.",
            "# Record a compliance marker as device-state evidence",
            "mkdir -p /var/lib/cs3",
            "printf 'baseline_applied_at=%s\\nhost=%s\\n' \"$(date -u +%FT%TZ)\" \"$(hostname)\" > /var/lib/cs3/endpoint-baseline.status",
            "echo 'CS3 endpoint baseline applied'"
          ]
        }
      }
    ]
  })

  tags = local.common_tags
}

# Enrollment: bind the baseline to every Project=cs3 instance, re-applied monthly.
resource "aws_ssm_association" "endpoint_baseline" {
  count            = local.endpoint_mgmt_enabled
  association_name = "${var.name_prefix}-endpoint-baseline${var.resource_suffix_part}"
  name             = aws_ssm_document.endpoint_baseline[0].name

  targets {
    key    = "tag:Project"
    values = ["cs3"]
  }

  schedule_expression = "rate(30 days)"

  # Tolerate single-node runs; surface failures without blocking.
  compliance_severity = "MEDIUM"
}

# Patch compliance reporting (non-disruptive scan; switch to "Install" for enforcement).
resource "aws_ssm_association" "patch_scan" {
  count            = local.endpoint_mgmt_enabled
  association_name = "${var.name_prefix}-patch-scan${var.resource_suffix_part}"
  name             = "AWS-RunPatchBaseline"

  targets {
    key    = "tag:Project"
    values = ["cs3"]
  }

  parameters = {
    Operation = "Scan"
  }

  schedule_expression = "rate(1 day)"
  compliance_severity = "MEDIUM"
}
