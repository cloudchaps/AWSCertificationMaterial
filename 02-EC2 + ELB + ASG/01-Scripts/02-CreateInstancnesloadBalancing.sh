#!/bin/bash

SECURITYGROUP="${1}"
TARGETGROUP="${2}"
VPCID="${3}"
LOADBALANCERNM="${4}"
shift 4 # Remove first 4 arguments, rest are instance names
EC2INSTANCES=("$@") # Array of instance names

# Validate load balancer name
if [[ ! "$LOADBALANCERNM" =~ ^[a-zA-Z0-9-]+$ ]]; then
  echo "❌ Load balancer name '${LOADBALANCERNM}' contains invalid characters. Only alphanumeric and hyphens allowed."
  exit 1
fi

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

# Get subnet IDs for the VPC
SUBNET_IDS_LOADBALANCER=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPCID}" --query 'Subnets[*].SubnetId' --output text)
if [ -z "$SUBNET_IDS" ]; then
  echo "❌ No subnets found for VPC for the load balancer${VPCID}!"
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
    
    # Get instance subnet and validate it's in our subnet list
    INSTANCE_SUBNET=$(aws ec2 describe-instances --instance-ids "${INSTANCE_ID}" --query 'Reservations[*].Instances[*].SubnetId' --output text)
    if [[ ! " $SUBNET_IDS " =~ " $INSTANCE_SUBNET " ]]; then
      echo "❌ Instance ${EC2INSTANCE} subnet ${INSTANCE_SUBNET} not found in VPC subnets!"
      exit 1
    fi
    
    aws ec2 create-tags --resources "${INSTANCE_ID}" --tags Key=Name,Value="${EC2INSTANCE}" >> ~/tmp/launch-logs.txt 2>&1
    echo "✅ Launched ${EC2INSTANCE} with ID: ${INSTANCE_ID}"
  else
    echo "ℹ️ Instance ${EC2INSTANCE} already exists, skipping."
  fi
done

# Create target group and add instances to load balance
echo "🎯 Creating target group for load balancing..."
TARGET_GROUP_ARN=$(aws elbv2 create-target-group --name "${TARGETGROUP}" \
                                                 --protocol HTTP \
                                                 --port 80 \
                                                 --vpc-id ${VPCID} \
                                                 --query 'TargetGroups[0].TargetGroupArn' \
                                                 --output text)
echo "✅ Created target group: ${TARGET_GROUP_ARN}"

# Wait for the instances to be up
echo "⏳ Waiting for instances to be in running state..."
for EC2INSTANCE in "${EC2INSTANCES[@]}"; do
  INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${EC2INSTANCE}" "Name=instance-state-name,Values=pending,running" --query 'Reservations[0].Instances[0].InstanceId' --output text)
  if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "None" ]; then
    aws ec2 wait instance-running --instance-ids "${INSTANCE_ID}"
    aws ec2 wait instance-status-ok --instance-ids "${INSTANCE_ID}"
    echo "✅ Instance ${EC2INSTANCE} (${INSTANCE_ID}) is running and ready"
  fi
done

# Add instances to target group
echo "🖥️ Adding instances to target group..."
for EC2INSTANCE in "${EC2INSTANCES[@]}"; do
  INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name, Values=${EC2INSTANCE}" --query 'Reservations[*].Instances[*].InstanceId' --output text)
  echo "🔗 Registering instance ${INSTANCE_ID} to target group..."
  aws elbv2 register-targets --target-group-arn "${TARGET_GROUP_ARN}" --targets Id="${INSTANCE_ID}" >> ~/tmp/launch-logs.txt 2>&1
done
echo "✅ Added all instances to target group."

# Create Application load balancer
echo "🌐 Creating Application Load Balancer..."

LOADBALANCER_ARN=$(aws elbv2 create-load-balancer --name "${LOADBALANCERNM}" \
                                                  --subnets $SUBNET_IDS_LOADBALANCER \
                                                  --security-groups "${SECURITYGROUP_ID}" \
                                                  --scheme internet-facing \
                                                  --type application \
                                                  --query 'LoadBalancers[0].LoadBalancerArn' \
                                                  --output text)
echo "✅ Created Load Balancer: ${LOADBALANCER_ARN}"

# Create listener to forward traffic from load balancer to target group
echo "🎧 Creating listener for Load Balancer..."
LISTENER_ARN=$(aws elbv2 create-listener --load-balancer-arn "${LOADBALANCER_ARN}" \
                                         --protocol HTTP \
                                         --port 80 \
                                         --default-actions Type=forward,TargetGroupArn="${TARGET_GROUP_ARN}" \
                                         --query 'Listeners[0].ListenerArn' \
                                         --output text)
echo "✅ Created Listener: ${LISTENER_ARN}"