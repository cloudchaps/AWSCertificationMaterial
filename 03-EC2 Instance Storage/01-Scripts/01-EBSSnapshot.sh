#!/bin/bash

VPCID="${1}"
EC2INSTANCE="${2}"
AZ_NM="${3}"
SECURITYGROUP="${4}"
shift 4 # Remove first 4 arguments, rest are instance names
AZS_COPY=("$@") # Array of subnet ids

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

# Launch template instance
echo "🚀 Launching template EC2 instance ${EC2INSTANCE}..."
SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPCID}" "Name=availability-zone,Values=${AZ_NM}" --query 'Subnets[0].SubnetId' --output text 2>&1)
if [ -z "$SUBNET_ID" ] || [ "$SUBNET_ID" = "None" ] || [[ "$SUBNET_ID" == *"error"* ]]; then
  echo "❌ No subnet found in AZ ${AZ_NM} for VPC ${VPCID}!"
  echo "Available subnets:"
  aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPCID}" --query 'Subnets[*].[SubnetId,AvailabilityZone]' --output table
  exit 1
fi
echo "✅ Found subnet: ${SUBNET_ID} in AZ ${AZ_NM}"

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
echo "✅ Instance is running"

# Wait additional time for user-data script to complete and create data
echo "⏳ Waiting for user-data script to complete (60 seconds)..."
sleep 60
echo "✅ User-data should be complete"

# Create a separate data volume and attach it to the instance
echo "💾 Creating separate data volume..."
DATA_VOLUME_ID=$(aws ec2 create-volume --availability-zone "${AZ_NM}" --size 1 --volume-type gp3 --query 'VolumeId' --output text)
aws ec2 create-tags --resources "${DATA_VOLUME_ID}" --tags Key=Name,Value="${EC2INSTANCE}-data" >> ~/tmp/launch-logs.txt 2>&1
echo "✅ Created data volume: ${DATA_VOLUME_ID}"

# Wait for data volume to be available
echo "⏳ Waiting for data volume to be available..."
aws ec2 wait volume-available --volume-ids "${DATA_VOLUME_ID}"
echo "✅ Data volume available"

# Attach data volume to instance
echo "🔗 Attaching data volume to instance..."
aws ec2 attach-volume --volume-id "${DATA_VOLUME_ID}" --instance-id "${INSTANCE_ID}" --device /dev/sdf >> ~/tmp/launch-logs.txt 2>&1
aws ec2 wait volume-in-use --volume-ids "${DATA_VOLUME_ID}"
echo "✅ Data volume attached"

# Format and mount the data volume, then copy data to it
echo "📝 Formatting data volume and copying data..."
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "${INSTANCE_ID}" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
echo "Instance public IP: ${PUBLIC_IP}"
echo "⚠️  You may need to manually SSH and run:"
echo "    sudo mkfs.xfs /dev/xvdf"
echo "    sudo mkdir -p /mnt/data-volume"
echo "    sudo mount /dev/xvdf /mnt/data-volume"
echo "    sudo cp -r /data/* /mnt/data-volume/"
echo "    sudo umount /mnt/data-volume"
echo "Waiting 30 seconds for manual setup..."
sleep 30

# Get the data volume ID
echo "💾 Getting data volume ID..."
DATA_VOLUME_ID=$(aws ec2 describe-volumes --filters "Name=tag:Name,Values=${EC2INSTANCE}-data" --query 'Volumes[0].VolumeId' --output text)
echo "✅ Data volume ID: ${DATA_VOLUME_ID}"

# Create snapshot from the data volume
echo "📸 Creating snapshot from data volume ${DATA_VOLUME_ID}..."
SNAPSHOT_ID=$(aws ec2 create-snapshot --volume-id "${DATA_VOLUME_ID}" --description "Snapshot of ${EC2INSTANCE} data" --query 'SnapshotId' --output text)
aws ec2 create-tags --resources "${SNAPSHOT_ID}" --tags Key=Name,Value="${EC2INSTANCE}-snapshot" >> ~/tmp/launch-logs.txt 2>&1
echo "✅ Created snapshot: ${SNAPSHOT_ID}"

# Wait for snapshot to complete
echo "⏳ Waiting for snapshot to complete..."
aws ec2 wait snapshot-completed --snapshot-ids "${SNAPSHOT_ID}"
echo "✅ Snapshot completed"

# Get availability zone from data volume
AZ=$(aws ec2 describe-volumes --volume-ids "${DATA_VOLUME_ID}" --query 'Volumes[0].AvailabilityZone' --output text)
echo "📍 Original data volume AZ: ${AZ}"

# Create volumes and launch instances in each AZ
for AZ_COPY in "${AZS_COPY[@]}"; do
  echo "\n🔄 Processing AZ ${AZ_COPY}..."
  
  # Get subnet in the AZ
  SUBNET_ID_COPY=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPCID}" "Name=availability-zone,Values=${AZ_COPY}" --query 'Subnets[0].SubnetId' --output text 2>&1)
  if [ -z "$SUBNET_ID_COPY" ] || [ "$SUBNET_ID_COPY" = "None" ] || [[ "$SUBNET_ID_COPY" == *"error"* ]]; then
    echo "⚠️ No subnet found in AZ ${AZ_COPY}, skipping..."
    continue
  fi
  echo "✅ Found subnet: ${SUBNET_ID_COPY} in AZ ${AZ_COPY}"
  
  # Create volume from snapshot in the AZ
  echo "💾 Creating volume from snapshot in ${AZ_COPY}..."
  NEW_VOLUME_ID=$(aws ec2 create-volume --snapshot-id "${SNAPSHOT_ID}" --availability-zone "${AZ_COPY}" --query 'VolumeId' --output text)
  aws ec2 create-tags --resources "${NEW_VOLUME_ID}" --tags Key=Name,Value="${EC2INSTANCE}-volume-${AZ_COPY}" >> ~/tmp/launch-logs.txt 2>&1
  echo "✅ Created volume: ${NEW_VOLUME_ID}"
  
  # Wait for volume to be available
  echo "⏳ Waiting for volume to be available..."
  aws ec2 wait volume-available --volume-ids "${NEW_VOLUME_ID}"
  echo "✅ Volume available"
  
  # Launch instance in the AZ
  INSTANCE_NAME="${EC2INSTANCE}-copy-${AZ_COPY}"
  echo "🚀 Launching instance ${INSTANCE_NAME}..."
  NEW_INSTANCE_ID=$(aws ec2 run-instances --image-id "ami-0532be01f26a3de55" \
                         --instance-type "t2.micro" \
                         --subnet-id "${SUBNET_ID_COPY}" \
                         --security-group-ids "${SECURITYGROUP_ID}" \
                         --associate-public-ip-address \
                         --user-data file://./05-BootScripts/02-copy-instance.sh \
                         --query 'Instances[0].InstanceId' --output text)
  
  aws ec2 create-tags --resources "${NEW_INSTANCE_ID}" --tags Key=Name,Value="${INSTANCE_NAME}" >> ~/tmp/launch-logs.txt 2>&1
  echo "✅ Launched ${INSTANCE_NAME} with ID: ${NEW_INSTANCE_ID}"
  
  # Wait for instance to be running
  echo "⏳ Waiting for instance to be running..."
  aws ec2 wait instance-running --instance-ids "${NEW_INSTANCE_ID}"
  echo "✅ Instance is running"
  
  # Attach volume to instance
  echo "🔗 Attaching volume ${NEW_VOLUME_ID} to instance ${NEW_INSTANCE_ID}..."
  aws ec2 attach-volume --volume-id "${NEW_VOLUME_ID}" --instance-id "${NEW_INSTANCE_ID}" --device /dev/sdf >> ~/tmp/launch-logs.txt 2>&1
  echo "✅ Volume attached - user-data script will mount it and display data"
done

echo "\n🎉 All operations completed successfully!"