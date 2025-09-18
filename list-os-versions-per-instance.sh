#!/bin/bash

# This script shows the OS version for all running instances in the current region.
# You could simply use the command below but it will not show the instance names, only instance-ids:
# `aws ssm describe-instance-information --query \ 
# "InstanceInformationList[].{InstanceId:InstanceId,PlatformType:PlatformType,PlatformName:PlatformName,PlatformVersion:PlatformVersion}" --output table`
# So we are combining the output from the two queries here to show both the OS version and the corresponding instance name.
# Prerequisites: you must be logged into AWS CLI with a specified default region and (if applicable) a specified profile.

# create a temporary file for the data
temp_file=$(mktemp)

# add header
echo -e "InstanceId\tName\tPlatformType\tPlatformName\tPlatformVersion" > "$temp_file"

# get data
aws ssm describe-instance-information --query "InstanceInformationList[].[InstanceId,PlatformType,PlatformName,PlatformVersion]" --output text | \
while read instance_id platform_type platform_name platform_version; do
  name=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$instance_id" "Name=key,Values=Name" --query "Tags[0].Value" --output text 2>/dev/null)
  echo -e "$instance_id\t${name:-"(no name)"}\t$platform_type\t$platform_name\t$platform_version" >> "$temp_file"
done

# format and display
column -t -s $'\t' "$temp_file"

# remove the temporary file
rm -f "$temp_file"
