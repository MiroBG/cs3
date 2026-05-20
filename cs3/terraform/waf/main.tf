resource "aws_wafv2_web_acl" "portal" {
  name        = "${var.name_prefix}-portal-waf"
  description = "WAF rules for the CS3 portal"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "cs3PortalWaf"
    sampled_requests_enabled   = true
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "cs3CommonRules"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimitPortal"
    priority = 2

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "cs3RateLimit"
      sampled_requests_enabled   = true
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-portal-waf"
  })
}

resource "aws_wafv2_web_acl_association" "portal" {
  count        = var.enable_association && var.portal_alb_arn != null ? 1 : 0
  resource_arn = var.portal_alb_arn
  web_acl_arn  = aws_wafv2_web_acl.portal.arn
}

output "web_acl_arn" {
  value = aws_wafv2_web_acl.portal.arn
}

output "web_acl_name" {
  value = aws_wafv2_web_acl.portal.name
}