#!/bin/bash

SECURITYGROUP="${1}"
VPCID="${2}"
shift 2 # Remove first 4 arguments, rest are instance names
EC2INSTANCES=("$@") # Array of instance names

# Get security group ID from name
echo "🔍 Getting security group ID for ${SECURITYGROUP}..."
SECURITYGROUP_ID=$(aws ec2 describe-security-groups --group-names ${SECURITYGROUP} --query 'SecurityGroups[0].GroupId' --output text)

if [ "$SECURITYGROUP_ID" = "None" ] || [ -z "$SECURITYGROUP_ID" ]; then
  echo "❌ Security group ${SECURITYGROUP} not found!"
  exit 1
fi

# Get subnet IDs for the VPC
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPCID}" --query 'Subnets[0].SubnetId' --output text)
if [ -z "$SUBNET_IDS" ]; then
  echo "❌ No subnets found for VPC ${VPCID}!"
  exit 1
fi

# Loop through each instance name
for EC2INSTANCE in "${EC2INSTANCES[@]}"; do
  echo "📋 Checking if EC2 instance ${EC2INSTANCE} already exists..."
  EXISTING=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${EC2INSTANCE}" "Name=instance-state-name,Values=running,pending,stopped,stopping" --query 'Reservations[*].Instances[*].InstanceId' --output text)
  
  if [ -z "$EXISTING" ]; then
    echo "🚀 Launching EC2 instance ${EC2INSTANCE}..."
    INSTANCE_ID=$(aws ec2 run-instances --image-id "ami-0532be01f26a3de55" \
                           --instance-type "t2.micro" \
                           --subnet-id "${SUBNET_IDS}"  \
                           --security-group-ids "${SECURITYGROUP_ID}" \
                           --associate-public-ip-address \
                           --user-data file://./05-BootScripts/01-helloworld.sh \
                           --query 'Instances[0].InstanceId' --output text)
    
    aws ec2 create-tags --resources "${INSTANCE_ID}" --tags Key=Name,Value="${EC2INSTANCE}" >> ~/tmp/launch-logs.txt 2>&1
    echo "✅ Launched ${EC2INSTANCE} with ID: ${INSTANCE_ID}"
  else
    echo "ℹ️ Instance ${EC2INSTANCE} already exists, skipping."
  fi
done