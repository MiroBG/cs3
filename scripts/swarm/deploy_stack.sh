#!/usr/bin/env bash
set -euo pipefail
# Usage: deploy_stack.sh <ssh_target> <ssh_key> <stack_file> [env_file]
# Example: ./deploy_stack.sh user@1.2.3.4 ~/.ssh/id_rsa cs3/docker_swarm_stack/portal-stack.yml .env

SSH_TARGET="$1"
SSH_KEY="$2"
STACK_FILE="$3"
ENV_FILE="${4:-}" 

if [[ -z "$SSH_TARGET" || -z "$SSH_KEY" || -z "$STACK_FILE" ]]; then
  echo "Usage: $0 <ssh_target> <ssh_key> <stack_file> [env_file]"
  exit 2
fi

REMOTE_STACK="/tmp/$(basename "$STACK_FILE")"

echo "Copying stack file to $SSH_TARGET:$REMOTE_STACK"
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$STACK_FILE" "$SSH_TARGET:$REMOTE_STACK"

if [[ -n "$ENV_FILE" ]]; then
  echo "Copying env file to $SSH_TARGET:/tmp/swarm.env"
  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$ENV_FILE" "$SSH_TARGET:/tmp/swarm.env"
  ENV_ARG="--env-file /tmp/swarm.env"
else
  ENV_ARG=""
fi

echo "Initializing swarm (if needed) and deploying stack"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_TARGET" bash -s <<EOF
set -euo pipefail
if ! docker info >/dev/null 2>&1; then
  echo "Docker not installed on target. Abort." >&2
  exit 3
fi

if ! docker node ls >/dev/null 2>&1; then
  echo "Initializing swarm on manager"
  docker swarm init || true
fi

docker stack deploy $ENV_ARG -c "$REMOTE_STACK" portal
EOF

echo "Stack deploy request sent. Check manager for status: docker stack ps portal"
