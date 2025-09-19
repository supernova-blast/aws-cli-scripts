#!/bin/bash

# This script shows all resources account-wide in all available regions.
# Prerequisites: you must be logged into AWS CLI with a specified default region and (if applicable) a specified profile.

# output file
output_file="aws_resources_report_$(date +'%d_%b_%Y').txt"

# regions array
mapfile -t regions < <(aws ec2 describe-regions --query "Regions[].RegionName" --output text | tr '\t' '\n' | sort)

# account
account_id=$(aws sts get-caller-identity --query "Account" --output text)

# Glacier-supported regions (avoid endpoint errors)
mapfile -t glacier_regions < <(aws ssm get-parameters-by-path \
  --path /aws/service/global-infrastructure/services/glacier/regions \
  --query "Parameters[].Value" --output text | tr '\t' '\n')

# test if value is in array
in_array() {
  local needle="$1"; shift
  local e; for e in "$@"; do [[ "$e" == "$needle" ]] && return 0; done
  return 1
}

{
  printf "AWS Account: %s\n" "$account_id"

  printf "\n=== S3 Buckets (Global) ===\n"
  aws s3 ls

  printf "\n=== IAM Users (Global) ===\n"
  aws iam list-users --query "Users[].UserName" --output table

  printf "\n=== IAM Roles (Global) ===\n"
  aws iam list-roles --query "Roles[].RoleName" --output table

  for region in "${regions[@]}"; do
    printf "\n=== Resources in %s ===\n" "$region"

    printf "\n- EC2 Instances:\n"
    aws ec2 describe-instances --region "$region" \
      --query "Reservations[].Instances[].InstanceId" --output table

    printf "\n- RDS Databases:\n"
    aws rds describe-db-instances --region "$region" \
      --query "DBInstances[].DBInstanceIdentifier" --output table 2>/dev/null

    printf "\n- S3 Glacier Vaults:\n"
    if in_array "$region" "${glacier_regions[@]}"; then
      aws glacier list-vaults --account-id "$account_id" --region "$region" \
        --query "VaultList[].VaultName" --output table 2>/dev/null
    else
      printf "Glacier not available in %s\n" "$region"
    fi

    printf "\n- Lambda Functions:\n"
    aws lambda list-functions --region "$region" \
      --query "Functions[].FunctionName" --output table 2>/dev/null

    printf "\n- CloudFormation Stacks:\n"
    aws cloudformation list-stacks --region "$region" \
      --query "StackSummaries[].StackName" --output table 2>/dev/null

    printf "\n- Classic ELBs:\n"
    aws elb describe-load-balancers --region "$region" \
      --query "LoadBalancerDescriptions[].LoadBalancerName" --output table 2>/dev/null

    printf "\n- ALB/NLB (ELBv2):\n"
    aws elbv2 describe-load-balancers --region "$region" \
      --query "LoadBalancers[].LoadBalancerName" --output table 2>/dev/null

    printf "\n- VPCs:\n"
    aws ec2 describe-vpcs --region "$region" \
      --query "Vpcs[].VpcId" --output table

    printf "\n- Security Groups:\n"
    aws ec2 describe-security-groups --region "$region" \
      --query "SecurityGroups[].{GroupId:GroupId,Name:GroupName}" --output table
  done

  printf "\nAll AWS resources listed.\n"
} > "$output_file"

printf "AWS resources report saved to %s\n" "$output_file"
