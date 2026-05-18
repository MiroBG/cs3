resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki-stack"
  namespace  = var.logging_namespace
  version    = "2.14.0"

  create_namespace = true

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
    name = var.logging_namespace
  }
}

resource "kubernetes_config_map" "fluent_bit_config" {
  metadata {
    name      = "fluent-bit-config"
    namespace = var.logging_namespace
  }

  data = {
    "fluent-bit.conf" = file("${path.module}/fluent-bit.conf")
  }

  depends_on = [kubernetes_namespace.logging]
}

output "loki_endpoint" {
  value = "http://loki.${var.logging_namespace}:3100"
}

output "grafana_endpoint" {
  value = "http://grafana.${var.logging_namespace}:80"
}

output "grafana_admin_user" {
  value = "admin"
}

output "grafana_admin_password" {
  value     = var.grafana_admin_password
  sensitive = true
}
