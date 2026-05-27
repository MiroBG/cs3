locals {
  resource_suffix_part = var.resource_suffix != "" ? "-${var.resource_suffix}" : ""
}

resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki-stack"
  namespace  = kubernetes_namespace.logging.metadata[0].name
  version    = var.loki_stack_chart_version

  create_namespace = false

  set {
    name  = "loki.persistence.enabled"
    value = "true"
  }

  set {
    name  = "loki.persistence.size"
    value = "10Gi"
  }

  set {
    name  = "fluent-bit.enabled"
    value = "true"
  }

  set {
    name  = "promtail.enabled"
    value = "true"
  }

  set {
    name  = "grafana.enabled"
    value = "true"
  }

  set {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }
}

resource "kubernetes_namespace" "logging" {
  metadata {
    name = "${var.logging_namespace}${local.resource_suffix_part}"
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations,
      metadata[0].labels
    ]
  }
}

resource "kubernetes_config_map" "fluent_bit_config" {
  metadata {
    name      = "fluent-bit-config"
    namespace = kubernetes_namespace.logging.metadata[0].name
  }

  data = {
    "fluent-bit.conf" = file("${path.module}/fluent-bit.conf")
  }

  depends_on = [kubernetes_namespace.logging]
}

output "loki_endpoint" {
  value = "http://loki.${kubernetes_namespace.logging.metadata[0].name}:3100"
}

output "grafana_endpoint" {
  value = "http://grafana.${kubernetes_namespace.logging.metadata[0].name}:80"
}

output "grafana_admin_user" {
  value = "admin"
}

output "grafana_admin_password" {
  value     = var.grafana_admin_password
  sensitive = true
}
