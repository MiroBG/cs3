#!/bin/bash
# Build and push CS3 portal Docker image to ECR

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <ECR_REPOSITORY_URL> <IMAGE_TAG>"
    echo "Example: $0 123456789012.dkr.ecr.eu-central-1.amazonaws.com/cs3-portal latest"
    exit 1
fi

ECR_REPO=$1
IMAGE_TAG=${2:-latest}
IMAGE_NAME="cs3-portal"

echo "🔨 Building $IMAGE_NAME Docker image..."
docker build -t "$IMAGE_NAME:$IMAGE_TAG" ./portal

echo "📦 Tagging image for ECR..."
docker tag "$IMAGE_NAME:$IMAGE_TAG" "$ECR_REPO:$IMAGE_TAG"
docker tag "$IMAGE_NAME:$IMAGE_TAG" "$ECR_REPO:latest"

echo "🚀 Pushing image to ECR..."
docker push "$ECR_REPO:$IMAGE_TAG"
docker push "$ECR_REPO:latest"

echo "✅ Image pushed successfully to $ECR_REPO"
echo "Image URL: $ECR_REPO:$IMAGE_TAG"
