#!/bin/bash

# This script prints all State Manager Associations per each region.
# Prerequisites: you must be logged into AWS CLI with a specified profile (if applicable).

for r in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do
  echo "=== $r ==="
  aws ssm list-associations --region "$r" --output json |
    jq -r --arg region "$r" '
      .Associations[] |
      {
        region: $region,
        id: .AssociationId,
        name: .Name,
        status: .Overview.Status,
        sched: (.ScheduleExpression // "-")
      } |
      @json' |
  while read -r row; do
    jq -r '
      .region   as $r |
      .id       as $id |
      .name     as $n |
      .status   as $s |
      .sched    as $sch |
      @sh "\($r) \($id) \($n) \($s) \($sch)"' <<< "$row" |
    xargs printf "%-12s %-36s %-45s %-10s %-20s\n"
  done
done
