#!/bin/bash
# Deploy CS3 portal application to Kubernetes

set -e

if [ $# -lt 6 ]; then
    echo "Usage: $0 <ECR_IMAGE_URL> <COGNITO_CLIENT_ID> <COGNITO_CLIENT_SECRET> <COGNITO_DOMAIN> <DB_HOST> <DB_PASSWORD> [PORTAL_URL]"
    echo "Example: $0 123456789012.dkr.ecr.eu-central-1.amazonaws.com/cs3-portal:latest client-id-xxx secret-xxx cs3-employees cs3-db.example.internal db-password http://203.0.113.10"
    exit 1
fi

ECR_IMAGE=$1
COGNITO_CLIENT_ID=$2
COGNITO_CLIENT_SECRET=$3
COGNITO_DOMAIN=$4
DB_HOST=$5
DB_PASSWORD=$6
PORTAL_URL=${7:-http://localhost}
PORTAL_DEMO_AUTH="false"

case "${COGNITO_DOMAIN,,}" in
    ""|"disabled"|"none"|"local")
        COGNITO_DOMAIN="disabled"
        PORTAL_DEMO_AUTH="true"
        ;;
esac

NAMESPACE="cs3-prod"
AWS_REGION=${AWS_REGION:-eu-central-1}
ECR_REGISTRY=${ECR_IMAGE%%/*}
FLASK_SECRET_KEY=$(openssl rand -hex 32)
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CS3_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
RENDER_DIR=$(mktemp -d)
trap 'rm -rf "$RENDER_DIR"' EXIT

echo "Deploying CS3 portal to Kubernetes..."

cp -R "$CS3_DIR/k8s/portal" "$RENDER_DIR/portal"

escape_sed_replacement() {
    printf '%s' "$1" | sed 's/[&|\\]/\\&/g'
}

# Render deployment manifests without mutating files tracked in git.
sed -i "s|PORTAL_ECR_IMAGE|$(escape_sed_replacement "$ECR_IMAGE")|g" "$RENDER_DIR/portal/deployment.yaml"
sed -i "s|COGNITO_DOMAIN_VALUE|$(escape_sed_replacement "$COGNITO_DOMAIN")|g" "$RENDER_DIR/portal/deployment.yaml"
sed -i "s|FLASK_SECRET_KEY_VALUE|$(escape_sed_replacement "$FLASK_SECRET_KEY")|g" "$RENDER_DIR/portal/deployment.yaml"
sed -i "s|COGNITO_CLIENT_ID_VALUE|$(escape_sed_replacement "$COGNITO_CLIENT_ID")|g" "$RENDER_DIR/portal/deployment.yaml"
sed -i "s|COGNITO_CLIENT_SECRET_VALUE|$(escape_sed_replacement "$COGNITO_CLIENT_SECRET")|g" "$RENDER_DIR/portal/deployment.yaml"
sed -i "s|DB_HOST_VALUE|$(escape_sed_replacement "$DB_HOST")|g" "$RENDER_DIR/portal/deployment.yaml"
sed -i "s|DB_PASSWORD_VALUE|$(escape_sed_replacement "$DB_PASSWORD")|g" "$RENDER_DIR/portal/deployment.yaml"
sed -i "s|PORTAL_URL_VALUE|$(escape_sed_replacement "$PORTAL_URL")|g" "$RENDER_DIR/portal/deployment.yaml"
sed -i "s|PORTAL_DEMO_AUTH_VALUE|$(escape_sed_replacement "$PORTAL_DEMO_AUTH")|g" "$RENDER_DIR/portal/deployment.yaml"

echo "Applying Kubernetes manifests..."
kubectl apply -f "$CS3_DIR/k8s/00-namespace.yaml"
kubectl apply -f "$CS3_DIR/k8s/rbac/portal-role.yaml"

echo "Creating ECR image pull secret..."
ECR_PASSWORD=$(aws ecr get-login-password --region "$AWS_REGION")
kubectl create secret docker-registry ecr-registry \
    --namespace "$NAMESPACE" \
    --docker-server="$ECR_REGISTRY" \
    --docker-username=AWS \
    --docker-password="$ECR_PASSWORD" \
    --dry-run=client \
    -o yaml \
    | kubectl apply -f -
unset ECR_PASSWORD

kubectl apply -f "$RENDER_DIR/portal/"

echo "Waiting for portal deployment to be ready..."
if ! kubectl rollout status deployment/cs3-portal -n "$NAMESPACE" --timeout=5m; then
    echo "ERROR: portal deployment did not become ready"
    echo "---- Pods ----"
    kubectl get pods -n "$NAMESPACE" -o wide || true
    echo "---- Deployment ----"
    kubectl describe deployment cs3-portal -n "$NAMESPACE" || true
    echo "---- Pod details ----"
    kubectl describe pods -n "$NAMESPACE" -l app=cs3-portal || true
    echo "---- Recent events ----"
    kubectl get events -n "$NAMESPACE" --sort-by=.lastTimestamp | tail -80 || true
    echo "---- Portal logs ----"
    kubectl logs -n "$NAMESPACE" -l app=cs3-portal --tail=120 || true
    exit 1
fi

echo "Portal service details:"
kubectl get svc cs3-portal-svc -n $NAMESPACE

LOAD_BALANCER_IP=$(kubectl get svc cs3-portal-svc -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
if [ -z "$LOAD_BALANCER_IP" ]; then
    LOAD_BALANCER_IP=$(kubectl get svc cs3-portal-svc -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
fi

if [ -n "$LOAD_BALANCER_IP" ]; then
    echo "Portal deployed successfully."
    echo "Access at: http://$LOAD_BALANCER_IP"
else
    echo "LoadBalancer IP not yet assigned. Check status with:"
    echo "   kubectl get svc cs3-portal-svc -n $NAMESPACE --watch"
fi
