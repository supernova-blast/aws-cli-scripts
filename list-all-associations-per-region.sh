#!/bin/bash
# List all regions
regions=$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text)
for r in $regions; do
  echo "=== $r ===" >&2
  # Get all association IDs in the region
  aws ssm list-associations \
    --region "$r" \
    --output json \
  | jq -r '.Associations[].AssociationId' \
  | while read -r assoc_id; do
      [ -z "$assoc_id" ] && continue
      # Describe each association and filter only ones with Overview.Status == "Success"
      aws ssm describe-association \
        --region "$r" \
        --association-id "$assoc_id" \
        --output json \
      | jq -r --arg region "$r" '
          .AssociationDescription as $a
          | $a.Overview.Status as $st
          | select($st == "Success")
          | "\($region)\t\($a.AssociationId)\t\($a.Name)\t\($st)\t\($a.ScheduleExpression // "-")"
        '
    done
done
