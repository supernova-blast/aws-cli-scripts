#!/bin/bash

# This script finds and lists all stopped EC2 instances in each region, prints instance ID, Name tag (if present), and instance type.
# Prerequisites: you must be logged into AWS CLI with a specified profile (if applicable).

echo "Finding all stopped EC2 instances across all regions..."
echo "======================================================"

# Get all available regions
regions=$(aws ec2 describe-regions --query "Regions[].RegionName" --output text)

for region in $regions; do
    echo ""
    echo "Checking region: $region"
    echo "------------------------"
    
    # Get stopped instances in this region
    instances=$(aws ec2 describe-instances \
        --region $region \
        --filters "Name=instance-state-name,Values=stopped" \
        --query "Reservations[*].Instances[*].[InstanceId,Tags[?Key=='Name'].Value|[0],InstanceType]" \
        --output text 2>/dev/null)
    
    if [ -n "$instances" ]; then
        echo "$instances"
    else
        echo "No stopped instances found"
    fi
done
