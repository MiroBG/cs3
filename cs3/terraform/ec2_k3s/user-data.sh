#!/bin/bash
set -e

# Log all output
exec > >(tee -a /var/log/user-data.log)
exec 2>&1

echo "====== Starting k3s + PostgreSQL Setup ======"
echo "Timestamp: $(date)"

# Update system
apt-get update
apt-get upgrade -y

# Install dependencies
apt-get install -y \
  curl \
  wget \
  git \
  docker.io \
  postgresql \
  postgresql-contrib \
  python3-pip \
  jq \
  unzip

# Start Docker
systemctl enable docker
systemctl start docker

echo "====== Installing k3s ======"
# Install k3s (lightweight Kubernetes)
export INSTALL_K3S_EXEC="--write-kubeconfig-mode 644"
curl -sfL https://get.k3s.io | sh -

# Wait for k3s to be ready
echo "Waiting for k3s to be ready..."
for i in {1..60}; do
  if kubectl get nodes &>/dev/null; then
    echo "k3s is ready!"
    break
  fi
  echo "Waiting... ($i/60)"
  sleep 5
done

# Add k3s to PATH
export PATH=$PATH:/usr/local/bin

echo "====== Configuring PostgreSQL ======"
# Configure PostgreSQL
sudo -u postgres psql <<EOF
ALTER USER postgres WITH PASSWORD '${db_password}';
CREATE DATABASE employees;
GRANT ALL PRIVILEGES ON DATABASE employees TO postgres;
EOF

# Configure PostgreSQL to accept connections from localhost
echo "host    all             all             127.0.0.1/32            scram-sha-256" >> /etc/postgresql/16/main/pg_hba.conf
echo "host    all             all             ::1/128                 scram-sha-256" >> /etc/postgresql/16/main/pg_hba.conf
echo "listen_addresses = '*'" >> /etc/postgresql/16/main/postgresql.conf

# Restart PostgreSQL
systemctl enable postgresql
systemctl restart postgresql

echo "====== Installing Helm ======"
# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "====== Installing Prometheus & Grafana ======"
# Add Helm repos
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Create monitoring namespace
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Install Prometheus
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values - <<EOF
grafana:
  enabled: true
  adminPassword: ${grafana_admin_password}
  service:
    type: NodePort
    nodePort: 30100
prometheus:
  prometheusSpec:
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 5Gi
EOF

echo "====== Setting up Portal Namespace ======"
# Create namespace for portal application
kubectl create namespace portal --dry-run=client -o yaml | kubectl apply -f -

echo "====== Creating kubeconfig Export ======"
# Export kubeconfig to accessible location
mkdir -p /opt/k3s
cp /etc/rancher/k3s/k3s.yaml /opt/k3s/kubeconfig.yaml
chmod 644 /opt/k3s/kubeconfig.yaml

echo "====== Setup Complete ======"
echo "Timestamp: $(date)"
echo ""
echo "=== Access Information ==="
echo "Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"
echo "Kubeconfig: /opt/k3s/kubeconfig.yaml"
echo "PostgreSQL: localhost:5432 (user: postgres, password in AWS Secrets Manager)"
echo "Grafana: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):30100"
echo "k3s API: https://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):6443"
