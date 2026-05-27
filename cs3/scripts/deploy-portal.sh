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
kubectl apply -f "$RENDER_DIR/portal/"

echo "Waiting for portal deployment to be ready..."
kubectl rollout status deployment/cs3-portal -n $NAMESPACE --timeout=5m

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
