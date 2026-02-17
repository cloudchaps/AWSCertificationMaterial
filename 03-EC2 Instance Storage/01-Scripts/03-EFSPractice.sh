#!/bin/bash

VPCID="${1}"
EC2INSTANCE_PREFIX="${2}"
SECURITYGROUP="${3}"
shift 3
AZS_COPY=("$@") # Array of AZ names

# Get security group ID from name
echo "🔍 Checking if security group ${SECURITYGROUP} exists..."
SECURITYGROUP_ID=$(aws ec2 describe-security-groups --group-names ${SECURITYGROUP} --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)

if [ "$SECURITYGROUP_ID" = "None" ] || [ -z "$SECURITYGROUP_ID" ]; then
  echo "📦 Creating security group ${SECURITYGROUP}..."
  SECURITYGROUP_ID=$(aws ec2 create-security-group \
    --group-name "${SECURITYGROUP}" \
    --description "Security group for EFS instances" \
    --vpc-id "${VPCID}" \
    --query 'GroupId' --output text)
  
  aws ec2 authorize-security-group-ingress \
    --group-id "${SECURITYGROUP_ID}" \
    --ip-permissions \
      IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges='[{CidrIp=0.0.0.0/0}]' \
      IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges='[{CidrIp=0.0.0.0/0}]' \
      IpProtocol=tcp,FromPort=2049,ToPort=2049,IpRanges='[{CidrIp=0.0.0.0/0}]' >> ~/tmp/launch-logs.txt 2>&1
  
  echo "✅ Created security group: ${SECURITYGROUP_ID}"
else
  echo "✅ Security group found: ${SECURITYGROUP_ID}"
fi

# Create EFS filesystem
echo "📁 Creating EFS filesystem..."
EFS_ID=$(aws efs create-file-system \
  --performance-mode generalPurpose \
  --throughput-mode bursting \
  --encrypted \
  --tags Key=Name,Value="${EC2INSTANCE_PREFIX}-efs" \
  --query 'FileSystemId' --output text)
echo "✅ Created EFS: ${EFS_ID}"

# Wait for EFS to be available
echo "⏳ Waiting for EFS to be available..."
aws efs describe-file-systems --file-system-id "${EFS_ID}" --query 'FileSystems[0].LifeCycleState' --output text
sleep 10
echo "✅ EFS is available"

# Create mount targets in each AZ
for AZ_COPY in "${AZS_COPY[@]}"; do
  echo "🔗 Creating mount target in AZ ${AZ_COPY}..."
  
  # Get subnet in the AZ
  SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPCID}" "Name=availability-zone,Values=${AZ_COPY}" --query 'Subnets[0].SubnetId' --output text)
  if [ -z "$SUBNET_ID" ] || [ "$SUBNET_ID" = "None" ]; then
    echo "⚠️ No subnet found in AZ ${AZ_COPY}, skipping..."
    continue
  fi
  
  MOUNT_TARGET_ID=$(aws efs create-mount-target \
    --file-system-id "${EFS_ID}" \
    --subnet-id "${SUBNET_ID}" \
    --security-groups "${SECURITYGROUP_ID}" \
    --query 'MountTargetId' --output text)
  echo "✅ Created mount target: ${MOUNT_TARGET_ID} in ${AZ_COPY}"
done

# Wait for mount targets to be available
echo "⏳ Waiting for mount targets to be available (30 seconds)..."
sleep 30
echo "✅ Mount targets should be available"

# Create shared HTML content on EFS (we'll do this from the first instance)
echo "📝 Shared EFS content will be created by the first instance"

# Launch instances in each AZ
INSTANCE_COUNT=0
for AZ_COPY in "${AZS_COPY[@]}"; do
  INSTANCE_COUNT=$((INSTANCE_COUNT + 1))
  INSTANCE_NAME="${EC2INSTANCE_PREFIX}-${INSTANCE_COUNT}"
  
  echo "\n🚀 Launching instance ${INSTANCE_NAME} in AZ ${AZ_COPY}..."
  
  # Get subnet in the AZ
  SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPCID}" "Name=availability-zone,Values=${AZ_COPY}" --query 'Subnets[0].SubnetId' --output text)
  if [ -z "$SUBNET_ID" ] || [ "$SUBNET_ID" = "None" ]; then
    echo "⚠️ No subnet found in AZ ${AZ_COPY}, skipping..."
    continue
  fi
  
  # Create user-data with EFS mount
  cat > /tmp/userdata-${INSTANCE_NAME}.sh <<USERDATA
#!/bin/bash
yum update -y
yum install -y amazon-efs-utils httpd
systemctl start httpd
systemctl enable httpd

# Mount EFS
mkdir -p /mnt/efs
mount -t efs ${EFS_ID}:/ /mnt/efs
echo "${EFS_ID}:/ /mnt/efs efs defaults,_netdev 0 0" >> /etc/fstab

# Create shared content on EFS (first instance only)
if [ ! -f /mnt/efs/shared-content.html ]; then
  cat > /mnt/efs/shared-content.html <<'EOF'
<div class="efs-data">
    <h2>📁 Shared EFS Content</h2>
    <p>This content is stored on Amazon EFS and shared across all instances in different Availability Zones!</p>
    <p><strong>EFS ID:</strong> ${EFS_ID}</p>
    <p><strong>Created:</strong> $(date '+%Y-%m-%d %H:%M:%S')</p>
    <p>All instances can read and write to this shared filesystem, demonstrating cross-AZ data availability.</p>
</div>
EOF
fi

# Get instance metadata
INSTANCE_ID=\$(ec2-metadata --instance-id | cut -d " " -f 2)
INSTANCE_TYPE=\$(ec2-metadata --instance-type | cut -d " " -f 2)
AVAIL_ZONE=\$(ec2-metadata --availability-zone | cut -d " " -f 2)
PRIVATE_IP=\$(ec2-metadata --local-ipv4 | cut -d " " -f 2)
PUBLIC_IP=\$(ec2-metadata --public-ipv4 | cut -d " " -f 2)

# Read shared content from EFS
EFS_CONTENT=\$(cat /mnt/efs/shared-content.html 2>/dev/null || echo "<p>EFS content not yet available</p>")

# Create HTML page
cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>EC2 with EFS</title>
    <style>
        body { font-family: Arial, sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); margin: 0; padding: 20px; }
        .container { max-width: 800px; margin: 50px auto; background: white; border-radius: 10px; box-shadow: 0 10px 30px rgba(0,0,0,0.3); padding: 40px; }
        h1 { color: #333; text-align: center; margin-bottom: 30px; }
        .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }
        .info-card { background: #f8f9fa; padding: 20px; border-radius: 8px; border-left: 4px solid #667eea; }
        .label { font-weight: bold; color: #667eea; font-size: 14px; text-transform: uppercase; }
        .value { font-size: 18px; color: #333; margin-top: 5px; word-break: break-all; }
        .efs-data { background: #d1ecf1; padding: 20px; border-radius: 8px; margin-top: 20px; border-left: 4px solid #17a2b8; }
        .efs-data h2 { color: #0c5460; margin-top: 0; }
        .footer { text-align: center; margin-top: 30px; color: #666; font-size: 14px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 EC2 Instance with EFS</h1>
        <div class="info-grid">
            <div class="info-card">
                <div class="label">Instance ID</div>
                <div class="value">\$INSTANCE_ID</div>
            </div>
            <div class="info-card">
                <div class="label">Instance Type</div>
                <div class="value">\$INSTANCE_TYPE</div>
            </div>
            <div class="info-card">
                <div class="label">Availability Zone</div>
                <div class="value">\$AVAIL_ZONE</div>
            </div>
            <div class="info-card">
                <div class="label">Private IP</div>
                <div class="value">\$PRIVATE_IP</div>
            </div>
            <div class="info-card">
                <div class="label">Public IP</div>
                <div class="value">\$PUBLIC_IP</div>
            </div>
            <div class="info-card">
                <div class="label">Hostname</div>
                <div class="value">\$(hostname -f)</div>
            </div>
        </div>
        \$EFS_CONTENT
        <div class="footer">AWS CloudChaps Training - EFS Demo</div>
    </div>
</body>
</html>
EOF
USERDATA
  
  # Launch instance
  INSTANCE_ID=$(aws ec2 run-instances --image-id "ami-0532be01f26a3de55" \
                         --instance-type "t2.micro" \
                         --subnet-id "${SUBNET_ID}" \
                         --security-group-ids "${SECURITYGROUP_ID}" \
                         --associate-public-ip-address \
                         --user-data file:///tmp/userdata-${INSTANCE_NAME}.sh \
                         --query 'Instances[0].InstanceId' --output text)
  
  aws ec2 create-tags --resources "${INSTANCE_ID}" --tags Key=Name,Value="${INSTANCE_NAME}" >> ~/tmp/launch-logs.txt 2>&1
  echo "✅ Launched ${INSTANCE_NAME} with ID: ${INSTANCE_ID}"
  
  # Clean up temp file
  rm -f /tmp/userdata-${INSTANCE_NAME}.sh
done

echo "\n🎉 All operations completed successfully!"
echo "EFS ID: ${EFS_ID}"
echo "Access any instance via browser to see shared EFS content"
