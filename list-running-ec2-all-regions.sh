#!/bin/bash

# List all running EC2 instances across all AWS regions. Shows InstanceId, Name tag, and InstanceType.
# Prerequisites: you must be logged into AWS CLI with a specified default region and (if applicable) a specified profile.

set -euo pipefail

echo "Finding all running EC2 instances across all regions..."
echo "======================================================="

# get all available regions visible to this account
regions=$(aws ec2 describe-regions --query "Regions[].RegionName" --output text)

for region in $regions; do
  echo ""
  echo "Checking region: $region"
  echo "--------------------------"

  # query running instances, printing: InstanceId, Name tag (or (no name)), InstanceType
  instances=$(
    aws ec2 describe-instances \
      --region "$region" \
      --filters "Name=instance-state-name,Values=running" \
      --query "Reservations[*].Instances[*].[InstanceId, Tags[?Key=='Name'].Value | [0], InstanceType]" \
      --output text 2>/dev/null || true
  )

  if [ -n "${instances:-}" ]; then
    echo "$instances"
  else
    echo "No running instances found"
  fi
done
