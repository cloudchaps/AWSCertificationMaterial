#!/bin/bash

SECURITYGROUP="${1}"
VPCID="${2}"
LAUNCH_TEMPLATE_NAME="${3}"
AUTOSCALING_GROUP_NAME="${4}"
TARGET_GROUP_NAME="${5}"
LOAD_BALANCER_NAME="${6}"
EC2INSTANCE="${7}"

# Get security group ID from name
echo "🔍 Checking if security group ${SECURITYGROUP} exists..."
SECURITYGROUP_ID=$(aws ec2 describe-security-groups --group-names ${SECURITYGROUP} --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)

if [ "$SECURITYGROUP_ID" = "None" ] || [ -z "$SECURITYGROUP_ID" ]; then
  echo "📦 Creating security group ${SECURITYGROUP}..."
  SECURITYGROUP_ID=$(aws ec2 create-security-group \
    --group-name "${SECURITYGROUP}" \
    --description "Security group for autoscaling instances" \
    --vpc-id "${VPCID}" \
    --query 'GroupId' --output text)
  
  aws ec2 authorize-security-group-ingress \
    --group-id "${SECURITYGROUP_ID}" \
    --ip-permissions \
      IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges='[{CidrIp=0.0.0.0/0}]' \
      IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges='[{CidrIp=0.0.0.0/0}]' >> ~/tmp/launch-logs.txt 2>&1
  
  echo "✅ Created security group: ${SECURITYGROUP_ID}"
else
  echo "✅ Security group found: ${SECURITYGROUP_ID}"
fi

# Get subnet ID for the VPC
SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPCID}" --query 'Subnets[0].SubnetId' --output text)
if [ -z "$SUBNET_ID" ]; then
  echo "❌ No subnets found for VPC ${VPCID}!"
  exit 1
fi

# Launch template instance
echo "🚀 Launching template EC2 instance ${EC2INSTANCE}..."
INSTANCE_ID=$(aws ec2 run-instances --image-id "ami-0532be01f26a3de55" \
                       --instance-type "t2.micro" \
                       --subnet-id "${SUBNET_ID}" \
                       --security-group-ids "${SECURITYGROUP_ID}" \
                       --associate-public-ip-address \
                       --user-data file://./05-BootScripts/01-helloworld.sh \
                       --query 'Instances[0].InstanceId' --output text)

aws ec2 create-tags --resources "${INSTANCE_ID}" --tags Key=Name,Value="${EC2INSTANCE}" >> ~/tmp/launch-logs.txt 2>&1
echo "✅ Launched ${EC2INSTANCE} with ID: ${INSTANCE_ID}"

# Wait for instance to be running
echo "⏳ Waiting for instance to be running..."
aws ec2 wait instance-running --instance-ids "${INSTANCE_ID}"
aws ec2 wait instance-status-ok --instance-ids "${INSTANCE_ID}"
echo "✅ Instance is running and ready"

# Create launch template from instance
echo "📋 Creating launch template ${LAUNCH_TEMPLATE_NAME} from instance..."
LAUNCH_TEMPLATE_ID=$(aws ec2 create-launch-template \
  --launch-template-name "${LAUNCH_TEMPLATE_NAME}" \
  --version-description "Template from ${EC2INSTANCE}" \
  --launch-template-data "{
    \"ImageId\":\"ami-0532be01f26a3de55\",
    \"InstanceType\":\"t2.micro\",
    \"SecurityGroupIds\":[\"${SECURITYGROUP_ID}\"],
    \"UserData\":\"$(base64 -w 0 ./05-BootScripts/01-helloworld.sh)\"
  }" \
  --query 'LaunchTemplate.LaunchTemplateId' --output text)
echo "✅ Created launch template: ${LAUNCH_TEMPLATE_ID}"

# Get all subnet IDs for autoscaling group and load balancer
SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPCID}" --query 'Subnets[*].SubnetId' --output text | tr '\t' ',')
SUBNET_IDS_SPACE=$(echo $SUBNET_IDS | tr ',' ' ')

# Create target group
echo "🎯 Creating target group ${TARGET_GROUP_NAME}..."
TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
  --name "${TARGET_GROUP_NAME}" \
  --protocol HTTP \
  --port 80 \
  --vpc-id "${VPCID}" \
  --health-check-enabled \
  --health-check-path / \
  --query 'TargetGroups[0].TargetGroupArn' --output text)
echo "✅ Created target group: ${TARGET_GROUP_ARN}"

# Create load balancer
echo "🌐 Creating load balancer ${LOAD_BALANCER_NAME}..."
LOAD_BALANCER_ARN=$(aws elbv2 create-load-balancer \
  --name "${LOAD_BALANCER_NAME}" \
  --subnets $SUBNET_IDS_SPACE \
  --security-groups "${SECURITYGROUP_ID}" \
  --scheme internet-facing \
  --type application \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)
echo "✅ Created load balancer: ${LOAD_BALANCER_ARN}"

# Create listener
echo "🎧 Creating listener for load balancer..."
LISTENER_ARN=$(aws elbv2 create-listener \
  --load-balancer-arn "${LOAD_BALANCER_ARN}" \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn="${TARGET_GROUP_ARN}" \
  --query 'Listeners[0].ListenerArn' --output text)
echo "✅ Created listener: ${LISTENER_ARN}"

# Create autoscaling group
echo "🔄 Creating autoscaling group ${AUTOSCALING_GROUP_NAME}..."
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "${AUTOSCALING_GROUP_NAME}" \
  --launch-template "LaunchTemplateName=${LAUNCH_TEMPLATE_NAME}" \
  --min-size 1 \
  --max-size 3 \
  --desired-capacity 2 \
  --target-group-arns "${TARGET_GROUP_ARN}" \
  --vpc-zone-identifier "${SUBNET_IDS}" \
  --tags "Key=Name,Value=${AUTOSCALING_GROUP_NAME}-instance,PropagateAtLaunch=true" >> ~/tmp/launch-logs.txt 2>&1
echo "✅ Created autoscaling group: ${AUTOSCALING_GROUP_NAME}"

# Terminate template instance
echo "🗑️ Terminating template instance ${INSTANCE_ID}..."
aws ec2 terminate-instances --instance-ids "${INSTANCE_ID}" >> ~/tmp/launch-logs.txt 2>&1
echo "✅ Template instance terminated"