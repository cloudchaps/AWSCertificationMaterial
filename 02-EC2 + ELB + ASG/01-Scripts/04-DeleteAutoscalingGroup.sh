#!/bin/bash

SECURITYGROUP="${1}"
TARGETGROUP="${2}"
LAUNCH_TEMPLATE_NAME="${3}"
AUTOSCALING_GROUP_NAME="${4}"
LOAD_BALANCER_NAME="${5}"

# Delete Autoscaling Group
echo "🔄 Deleting Autoscaling Group ${AUTOSCALING_GROUP_NAME}..."
ASG_EXISTS=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "${AUTOSCALING_GROUP_NAME}" --query 'AutoScalingGroups[0].AutoScalingGroupName' --output text 2>/dev/null)
if [ -n "$ASG_EXISTS" ] && [ "$ASG_EXISTS" != "None" ]; then
  aws autoscaling delete-auto-scaling-group --auto-scaling-group-name "${AUTOSCALING_GROUP_NAME}" --force-delete >> ~/tmp/terminate-logs.txt 2>&1
  echo "⏳ Waiting for autoscaling group instances to terminate..."
  sleep 60
  echo "✅ Deleted Autoscaling Group"
else
  echo "ℹ️ Autoscaling Group ${AUTOSCALING_GROUP_NAME} not found"
fi

# Delete Load Balancer
echo "🌐 Deleting Load Balancer ${LOAD_BALANCER_NAME}..."
LOADBALANCER_ARN=$(aws elbv2 describe-load-balancers --names "${LOAD_BALANCER_NAME}" --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)
if [ -n "$LOADBALANCER_ARN" ] && [ "$LOADBALANCER_ARN" != "None" ]; then
  aws elbv2 delete-load-balancer --load-balancer-arn "${LOADBALANCER_ARN}" >> ~/tmp/terminate-logs.txt 2>&1
  echo "⏳ Waiting for load balancer to be deleted..."
  aws elbv2 wait load-balancers-deleted --load-balancer-arns "${LOADBALANCER_ARN}"
  echo "✅ Deleted Load Balancer"
else
  echo "ℹ️ Load Balancer ${LOAD_BALANCER_NAME} not found"
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

# Delete Launch Template
echo "📋 Deleting Launch Template ${LAUNCH_TEMPLATE_NAME}..."
LAUNCH_TEMPLATE_EXISTS=$(aws ec2 describe-launch-templates --launch-template-names "${LAUNCH_TEMPLATE_NAME}" --query 'LaunchTemplates[0].LaunchTemplateName' --output text 2>/dev/null)
if [ -n "$LAUNCH_TEMPLATE_EXISTS" ] && [ "$LAUNCH_TEMPLATE_EXISTS" != "None" ]; then
  aws ec2 delete-launch-template --launch-template-name "${LAUNCH_TEMPLATE_NAME}" >> ~/tmp/terminate-logs.txt 2>&1
  echo "✅ Deleted Launch Template"
else
  echo "ℹ️ Launch Template ${LAUNCH_TEMPLATE_NAME} not found"
fi

# Delete Security Group
echo "🔒 Deleting Security Group ${SECURITYGROUP}..."
SECURITYGROUP_ID=$(aws ec2 describe-security-groups --group-names "${SECURITYGROUP}" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
if [ -n "$SECURITYGROUP_ID" ] && [ "$SECURITYGROUP_ID" != "None" ]; then
  aws ec2 delete-security-group --group-id "${SECURITYGROUP_ID}" >> ~/tmp/terminate-logs.txt 2>&1
  echo "✅ Deleted Security Group"
else
  echo "ℹ️ Security Group ${SECURITYGROUP} not found"
fi