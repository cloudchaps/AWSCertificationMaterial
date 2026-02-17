#!/bin/bash

SECURITYGROUP="${1}"
TARGETGROUP="${2}"
VPCID="${3}"
LOADBALANCERNM="${4}"
shift 4 # Remove first 4 arguments, rest are instance names
EC2INSTANCES=("$@") # Array of instance names

# Delete Load Balancer
echo "🌐 Deleting Load Balancer ${LOADBALANCERNM}..."
LOADBALANCER_ARN=$(aws elbv2 describe-load-balancers --names "${LOADBALANCERNM}" --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)
if [ -n "$LOADBALANCER_ARN" ] && [ "$LOADBALANCER_ARN" != "None" ]; then
  aws elbv2 delete-load-balancer --load-balancer-arn "${LOADBALANCER_ARN}" >> ~/tmp/terminate-logs.txt 2>&1
  echo "⏳ Waiting for load balancer to be deleted..."
  aws elbv2 wait load-balancers-deleted --load-balancer-arns "${LOADBALANCER_ARN}"
  echo "✅ Deleted Load Balancer"
else
  echo "ℹ️ Load Balancer ${LOADBALANCERNM} not found"
fi

# Delete Target Group
echo "🎯 Deleting Target Group ${TARGETGROUP}..."
TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups --names "${TARGETGROUP}" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)
if [ -n "$TARGET_GROUP_ARN" ] && [ "$TARGET_GROUP_ARN" != "None" ]; then
  aws elbv2 delete-target-group --target-group-arn "${TARGET_GROUP_ARN}" >> ~/tmp/terminate-logs.txt 2>&1
  echo "✅ Deleted Target Group"
else
  echo "ℹ️ Target Group ${TARGETGROUP} not found"
fi

# Terminate EC2 Instances
for EC2INSTANCE in "${EC2INSTANCES[@]}"; do
  echo "📋 Checking if EC2 instance ${EC2INSTANCE} exists..."
  INSTANCE_IDS=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${EC2INSTANCE}" "Name=instance-state-name,Values=running,pending,stopped,stopping" --query 'Reservations[*].Instances[*].InstanceId' --output text)
  
  if [ -n "$INSTANCE_IDS" ]; then
    echo "🗑️ Terminating instances: ${INSTANCE_IDS}..."
    aws ec2 terminate-instances --instance-ids ${INSTANCE_IDS} >> ~/tmp/terminate-logs.txt 2>&1
    echo "✅ Terminated ${EC2INSTANCE}"
  else
    echo "ℹ️ No instances found with name ${EC2INSTANCE}"
  fi
done

# Wait for all instances to be terminated
echo "⏳ Waiting for all instances to be terminated..."
for EC2INSTANCE in "${EC2INSTANCES[@]}"; do
  INSTANCE_IDS=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${EC2INSTANCE}" "Name=instance-state-name,Values=shutting-down,running,stopping,stopped" --query 'Reservations[*].Instances[*].InstanceId' --output text)
  if [ -n "$INSTANCE_IDS" ]; then
    for INSTANCE_ID in $INSTANCE_IDS; do
      aws ec2 wait instance-terminated --instance-ids "${INSTANCE_ID}"
    done
  fi
done
echo "✅ All instances terminated"

# Delete Security Group
echo "🔒 Deleting Security Group ${SECURITYGROUP}..."
SECURITYGROUP_ID=$(aws ec2 describe-security-groups --group-names "${SECURITYGROUP}" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
if [ -n "$SECURITYGROUP_ID" ] && [ "$SECURITYGROUP_ID" != "None" ]; then
  aws ec2 delete-security-group --group-id "${SECURITYGROUP_ID}" >> ~/tmp/terminate-logs.txt 2>&1
  echo "✅ Deleted Security Group"
else
  echo "ℹ️ Security Group ${SECURITYGROUP} not found"
fi