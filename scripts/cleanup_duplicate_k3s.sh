#!/usr/bin/env bash
set -euo pipefail

# Helper script to clean up duplicate k3s instances
# Usage: ./cleanup_duplicate_instances.sh [name-prefix] [keep-latest]
# Example: ./cleanup_duplicate_instances.sh cs3 true

NAME_PREFIX="${1:-cs3}"
KEEP_LATEST="${2:-true}"
INSTANCE_NAME="${NAME_PREFIX}-k3s"

echo "Finding instances matching: $INSTANCE_NAME"
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running,stopped" \
  --query "Reservations[].Instances[].[InstanceId,LaunchTime,State.Name]" \
  --output table

INSTANCES=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running,stopped" \
  --query "Reservations[].Instances[].[InstanceId,LaunchTime]" \
  --output json)

COUNT=$(echo "$INSTANCES" | jq '. | length')

if [[ $COUNT -le 1 ]]; then
  echo "✓ Only 1 instance or fewer. Nothing to clean up."
  exit 0
fi

echo ""
echo "Found $COUNT instances. Sorting by launch time..."

# Sort by launch time (newest last) and delete all but the latest
if [[ "$KEEP_LATEST" == "true" ]]; then
  TO_DELETE=$(echo "$INSTANCES" | jq -r '.[] | select(.LaunchTime != (. | max_by(.LaunchTime) | .LaunchTime)) | .InstanceId' | head -n $((COUNT - 1)))
  
  if [[ -z "$TO_DELETE" ]]; then
    echo "✓ No older instances to delete."
    exit 0
  fi

  echo "Deleting older instances:"
  echo "$TO_DELETE" | while read INSTANCE_ID; do
    echo "  Terminating $INSTANCE_ID"
    aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" >/dev/null
  done
  echo "✓ Terminated older instances."
else
  echo "Would delete (dry-run):"
  echo "$INSTANCES" | jq -r '.[] | .InstanceId'
fi

echo ""
echo "After cleanup, SSH into the remaining instance:"
PUBLIC_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

if [[ -n "$PUBLIC_IP" && "$PUBLIC_IP" != "None" ]]; then
  echo "  ssh -i <key-file> ubuntu@$PUBLIC_IP"
else
  LATEST_ID=$(echo "$INSTANCES" | jq -r '.[-1].InstanceId')
  echo "  aws ec2-instance-connect open-tunnel --instance-id $LATEST_ID"
fi
