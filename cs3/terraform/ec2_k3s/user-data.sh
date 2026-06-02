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

apt-get install -y awscli || true
if ! command -v aws >/dev/null 2>&1; then
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install
fi

# Start Docker
systemctl enable docker
systemctl start docker

echo "====== Installing k3s ======"
# Install k3s (lightweight Kubernetes)
export INSTALL_K3S_EXEC="--write-kubeconfig-mode 644 --tls-san $${PUBLIC_IP}"
curl -sfL https://get.k3s.io | sh -

# Wait for k3s to be ready
echo "Waiting for k3s to be ready..."
K3S_READY=false
for i in {1..60}; do
  if systemctl is-active --quiet k3s && kubectl get nodes &>/dev/null; then
    echo "k3s is ready!"
    K3S_READY=true
    break
  fi
  echo "Waiting... ($i/60)"
  systemctl --no-pager --full status k3s || true
  sleep 5
done

if [ "$K3S_READY" != "true" ]; then
  echo "ERROR: k3s did not become ready; refusing to publish a broken kubeconfig"
  journalctl -u k3s --no-pager -n 120 || true
  exit 1
fi

echo "Waiting for k3s API socket on port 6443..."
for i in {1..60}; do
  if ss -ltn | grep -q ':6443 '; then
    echo "k3s API is listening on 6443"
    break
  fi
  echo "Waiting for 6443 listener... ($i/60)"
  sleep 5
done

if ! ss -ltn | grep -q ':6443 '; then
  echo "ERROR: k3s API was ready locally but port 6443 is not listening"
  journalctl -u k3s --no-pager -n 120 || true
  exit 1
fi

# Export kubeconfig as soon as k3s is available so SSM can fetch it while the
# rest of bootstrap continues.
echo "====== Creating kubeconfig Export ======"
mkdir -p /opt/k3s
cp /etc/rancher/k3s/k3s.yaml /opt/k3s/kubeconfig.yaml
sed -i "s|https://127.0.0.1:6443|https://$${PUBLIC_IP}:6443|g" /opt/k3s/kubeconfig.yaml
chmod 644 /opt/k3s/kubeconfig.yaml

echo "====== Publishing kubeconfig to SSM Parameter Store ======"
if command -v aws >/dev/null 2>&1 && [ -n "$AWS_REGION" ]; then
  for i in 1 2 3 4 5 6; do
    if aws ssm put-parameter \
      --region "$${AWS_REGION}" \
      --name "${kubeconfig_parameter}" \
      --type "String" \
      --value file:///opt/k3s/kubeconfig.yaml \
      --tier "Advanced" \
      --overwrite >/dev/null; then
      echo "Published kubeconfig to ${kubeconfig_parameter}"
      break
    fi
    echo "Retrying kubeconfig publish to Parameter Store ($i/6)..."
    sleep 10
  done
else
  echo "AWS CLI or AWS region missing; skipping kubeconfig Parameter Store publish"
fi

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

echo "====== Initializing Employee Database Schema ======"
sudo -u postgres psql -d employees <<'EOF'
CREATE TABLE IF NOT EXISTS employees (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    department VARCHAR(255),
    status VARCHAR(50) NOT NULL DEFAULT 'active',
    role VARCHAR(50) NOT NULL DEFAULT 'employee',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    offboarded_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_email ON employees(email);
CREATE INDEX IF NOT EXISTS idx_status ON employees(status);
CREATE INDEX IF NOT EXISTS idx_department ON employees(department);

CREATE TABLE IF NOT EXISTS employee_audit_log (
    id SERIAL PRIMARY KEY,
    employee_id INTEGER NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    action VARCHAR(50) NOT NULL,
    old_status VARCHAR(50),
    new_status VARCHAR(50),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    performed_by VARCHAR(255)
);

CREATE INDEX IF NOT EXISTS idx_employee_audit ON employee_audit_log(employee_id);
CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON employee_audit_log(timestamp);

CREATE TABLE IF NOT EXISTS employee_requests (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL REFERENCES employees(email) ON DELETE CASCADE,
    request_type VARCHAR(50) NOT NULL,
    description TEXT NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP,
    resolved_by VARCHAR(255)
);

CREATE INDEX IF NOT EXISTS idx_request_email ON employee_requests(email);
CREATE INDEX IF NOT EXISTS idx_request_status ON employee_requests(status);
CREATE INDEX IF NOT EXISTS idx_request_created ON employee_requests(created_at);

INSERT INTO employees (email, name, department, status, role)
VALUES
    ('admin@innovatech.local', 'System Admin', 'IT', 'active', 'admin'),
    ('hr@innovatech.local', 'HR Manager', 'HR', 'active', 'hr'),
    ('john.doe@innovatech.local', 'John Doe', 'Engineering', 'pending', 'employee'),
    ('jane.smith@innovatech.local', 'Jane Smith', 'Operations', 'active', 'employee')
ON CONFLICT (email) DO NOTHING;
EOF

# Configure PostgreSQL to accept connections from localhost
echo "host    all             all             127.0.0.1/32            scram-sha-256" >> /etc/postgresql/16/main/pg_hba.conf
echo "host    all             all             ::1/128                 scram-sha-256" >> /etc/postgresql/16/main/pg_hba.conf
echo "host    all             all             10.0.0.0/8              scram-sha-256" >> /etc/postgresql/16/main/pg_hba.conf
echo "host    all             all             172.16.0.0/12           scram-sha-256" >> /etc/postgresql/16/main/pg_hba.conf
echo "host    all             all             192.168.0.0/16          scram-sha-256" >> /etc/postgresql/16/main/pg_hba.conf
echo "listen_addresses = '*'" >> /etc/postgresql/16/main/postgresql.conf

# Restart PostgreSQL
systemctl enable postgresql
systemctl restart postgresql

echo "====== Configuring PostgreSQL Streaming Replication (local standby) ======"
# Single-vCPU constraint: a second EC2 node / RDS Multi-AZ is not available, so we
# run a warm standby cluster on the SAME host (port 5433) via streaming replication.
# This demonstrates database failover (promote standby + repoint portal); physical
# node-level HA remains an accepted residual risk documented in the Phase 4 report.
PG_VER=16
PRIMARY_HBA="/etc/postgresql/$${PG_VER}/main/pg_hba.conf"
PRIMARY_CONF="/etc/postgresql/$${PG_VER}/main/postgresql.conf"

cat >> "$${PRIMARY_CONF}" <<'PGCONF'
wal_level = replica
max_wal_senders = 5
max_replication_slots = 5
hot_standby = on
wal_keep_size = 128MB
PGCONF

# Trust replication over loopback only (single-host demo); never exposed off-box.
echo "host    replication     replicator      127.0.0.1/32            trust" >> "$${PRIMARY_HBA}"

sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='replicator'" | grep -q 1 \
  || sudo -u postgres psql -c "CREATE ROLE replicator WITH REPLICATION LOGIN;"

systemctl restart postgresql@$${PG_VER}-main || systemctl restart postgresql

# Build the standby cluster (best-effort; must never break boot).
{
  pg_dropcluster --stop $${PG_VER} standby 2>/dev/null || true
  pg_createcluster $${PG_VER} standby
  pg_ctlcluster $${PG_VER} standby stop || true
  STANDBY_DATA="/var/lib/postgresql/$${PG_VER}/standby"
  rm -rf "$${STANDBY_DATA}"/*
  sudo -u postgres pg_basebackup -h 127.0.0.1 -p 5432 -U replicator \
    -D "$${STANDBY_DATA}" -Fp -Xs -P -R -C -S standby_slot
  echo "port = 5433" >> "/etc/postgresql/$${PG_VER}/standby/postgresql.conf"
  chown -R postgres:postgres "$${STANDBY_DATA}"
  pg_ctlcluster $${PG_VER} standby start
  echo "Standby cluster streaming from primary; listening on 127.0.0.1:5433"
} || echo "WARN: standby replication setup failed; primary on 5432 remains available"

echo "====== Installing Helm ======"
# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "====== Preparing Monitoring Namespace ======"
# Keep bootstrapping light for single-vCPU student accounts. The GitHub Actions
# deployment installs the lightweight Prometheus/Grafana manifests after k3s is reachable.
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

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
echo "Grafana: http://$${PUBLIC_IP}:30100 (after GitHub Actions monitoring step)"
echo "k3s API: https://$${PUBLIC_IP}:6443"
