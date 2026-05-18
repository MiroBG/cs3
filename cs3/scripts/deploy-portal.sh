#!/bin/bash
# Deploy CS3 portal application to Kubernetes

set -e

if [ $# -lt 4 ]; then
    echo "Usage: $0 <ECR_IMAGE_URL> <COGNITO_CLIENT_ID> <COGNITO_CLIENT_SECRET> <COGNITO_DOMAIN> [RDS_HOST] [DB_PASSWORD]"
    echo "Example: $0 123456789012.dkr.ecr.eu-central-1.amazonaws.com/cs3-portal:latest client-id-xxx secret-xxx cs3-employees-prod rds.amazonaws.com admin-password"
    exit 1
fi

ECR_IMAGE=$1
COGNITO_CLIENT_ID=$2
COGNITO_CLIENT_SECRET=$3
COGNITO_DOMAIN=$4
RDS_HOST=${5:-rds.amazonaws.com}
DB_PASSWORD=${6:-changeme}

NAMESPACE="default"
FLASK_SECRET_KEY=$(openssl rand -hex 32)

echo "🚀 Deploying CS3 portal to Kubernetes..."

# Update deployment manifest with actual values
sed -i "s|PORTAL_ECR_IMAGE|$ECR_IMAGE|g" ./k8s/portal/deployment.yaml
sed -i "s|COGNITO_DOMAIN_VALUE|$COGNITO_DOMAIN|g" ./k8s/portal/deployment.yaml
sed -i "s|FLASK_SECRET_KEY_VALUE|$FLASK_SECRET_KEY|g" ./k8s/portal/deployment.yaml
sed -i "s|COGNITO_CLIENT_ID_VALUE|$COGNITO_CLIENT_ID|g" ./k8s/portal/deployment.yaml
sed -i "s|COGNITO_CLIENT_SECRET_VALUE|$COGNITO_CLIENT_SECRET|g" ./k8s/portal/deployment.yaml
sed -i "s|RDS_HOST_VALUE|$RDS_HOST|g" ./k8s/portal/deployment.yaml
sed -i "s|RDS_PASSWORD_VALUE|$DB_PASSWORD|g" ./k8s/portal/deployment.yaml

echo "📝 Applying Kubernetes manifests..."
kubectl apply -f ./k8s/portal/

echo "⏳ Waiting for portal deployment to be ready..."
kubectl rollout status deployment/cs3-portal -n $NAMESPACE --timeout=5m

echo "🔍 Portal service details:"
kubectl get svc cs3-portal-svc -n $NAMESPACE

LOAD_BALANCER_IP=$(kubectl get svc cs3-portal-svc -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
if [ -z "$LOAD_BALANCER_IP" ]; then
    LOAD_BALANCER_IP=$(kubectl get svc cs3-portal-svc -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
fi

if [ -n "$LOAD_BALANCER_IP" ]; then
    echo "✅ Portal deployed successfully!"
    echo "📍 Access at: http://$LOAD_BALANCER_IP"
else
    echo "⚠️ LoadBalancer IP not yet assigned. Check status with:"
    echo "   kubectl get svc cs3-portal-svc -n $NAMESPACE --watch"
fi
