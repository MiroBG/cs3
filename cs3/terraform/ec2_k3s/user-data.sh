#!/bin/bash
set -e

# Log all output
exec > >(tee -a /var/log/user-data.log)
exec 2>&1

echo "====== Starting k3s + PostgreSQL Setup ======"
echo "Timestamp: $(date)"

# Minimal bootstrap dependencies used before the full package install below.
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates

get_metadata() {
  local path="$1"
  local token
  token=$(curl -fsS -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || true)
  if [ -n "$token" ]; then
    curl -fsS -H "X-aws-ec2-metadata-token: $token" "http://169.254.169.254/latest/$${path}"
  else
    curl -fsS "http://169.254.169.254/latest/$${path}"
  fi
}

AWS_REGION=$(get_metadata dynamic/instance-identity/document | sed -n 's/.*"region"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
PUBLIC_IP="${eip_public_ip}"
if [ -z "$PUBLIC_IP" ]; then
  PUBLIC_IP=$(get_metadata meta-data/public-ipv4)
fi

# Update system
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

echo "====== Installing SSM Agent ======"
if [ -n "$AWS_REGION" ]; then
  SSM_DEB="/tmp/amazon-ssm-agent.deb"
  for i in 1 2 3; do
    if curl -fsSL "https://s3.$${AWS_REGION}.amazonaws.com/amazon-ssm-$${AWS_REGION}/latest/debian_amd64/amazon-ssm-agent.deb" -o "$SSM_DEB"; then
      dpkg -i "$SSM_DEB" && break
    fi
    echo "Retrying amazon-ssm-agent deb install ($i/3)..."
    sleep 10
  done
fi

if ! systemctl list-unit-files | grep -q '^amazon-ssm-agent.service'; then
  echo "Falling back to Snap install for SSM agent"
  apt-get install -y snapd
  systemctl enable --now snapd.socket || true
  snap wait system seed.loaded || true
  snap install amazon-ssm-agent --classic || true
fi

if systemctl list-unit-files | grep -q '^amazon-ssm-agent.service'; then
  systemctl enable --now amazon-ssm-agent
elif systemctl list-unit-files | grep -q '^snap.amazon-ssm-agent.amazon-ssm-agent.service'; then
  systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent.service
fi

for i in 1 2 3 4 5 6; do
  if systemctl is-active amazon-ssm-agent >/dev/null 2>&1 || systemctl is-active snap.amazon-ssm-agent.amazon-ssm-agent.service >/dev/null 2>&1; then
    echo "SSM agent is active"
    break
  fi
  echo "Waiting for SSM agent service to become active ($i/6)..."
  sleep 5
done

if systemctl is-active amazon-ssm-agent >/dev/null 2>&1; then
  amazon-ssm-agent -version || true
elif systemctl is-active snap.amazon-ssm-agent.amazon-ssm-agent.service >/dev/null 2>&1; then
  /snap/bin/amazon-ssm-agent -version || true
fi

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
export INSTALL_K3S_EXEC="--write-kubeconfig-mode 644 --tls-san $${PUBLIC_IP}"
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

# Export kubeconfig as soon as k3s is available so SSM can fetch it while the
# rest of bootstrap continues.
echo "====== Creating kubeconfig Export ======"
mkdir -p /opt/k3s
cp /etc/rancher/k3s/k3s.yaml /opt/k3s/kubeconfig.yaml
sed -i "s|https://127.0.0.1:6443|https://$${PUBLIC_IP}:6443|g" /opt/k3s/kubeconfig.yaml
chmod 644 /opt/k3s/kubeconfig.yaml

echo "====== Refreshing SSM Agent ======"
if systemctl list-unit-files | grep -q '^amazon-ssm-agent.service'; then
  systemctl restart amazon-ssm-agent || true
elif systemctl list-unit-files | grep -q '^snap.amazon-ssm-agent.amazon-ssm-agent.service'; then
  systemctl restart snap.amazon-ssm-agent.amazon-ssm-agent.service || true
fi

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

echo "====== Setup Complete ======"
echo "Timestamp: $(date)"
echo ""
echo "=== Access Information ==="
echo "Public IP: $${PUBLIC_IP}"
echo "Kubeconfig: /opt/k3s/kubeconfig.yaml"
echo "PostgreSQL: localhost:5432 (user: postgres, password in AWS Secrets Manager)"
echo "Grafana: http://$${PUBLIC_IP}:30100"
echo "k3s API: https://$${PUBLIC_IP}:6443"
