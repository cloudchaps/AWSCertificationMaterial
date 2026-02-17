#!/bin/bash

VPCID="${1}"
EC2INSTANCE="${2}"
AZ_NM="${3}"
SECURITYGROUP="${4}"
shift 4 # Remove first 4 arguments, rest are AZ names
AZS_COPY=("$@") # Array of AZ names

# Terminate all copy instances
for AZ_COPY in "${AZS_COPY[@]}"; do
  INSTANCE_NAME="${EC2INSTANCE}-copy-${AZ_COPY}"
  echo "🗑️ Terminating instance ${INSTANCE_NAME}..."
  INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${INSTANCE_NAME}" "Name=instance-state-name,Values=running,pending,stopped,stopping" --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null)
  
  if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "None" ]; then
    aws ec2 terminate-instances --instance-ids "${INSTANCE_ID}" >> ~/tmp/terminate-logs.txt 2>&1
    echo "✅ Terminated ${INSTANCE_NAME} (${INSTANCE_ID})"
  else
    echo "ℹ️ Instance ${INSTANCE_NAME} not found"
  fi
done

# Terminate original instance
echo "🗑️ Terminating original instance ${EC2INSTANCE}..."
ORIG_INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${EC2INSTANCE}" "Name=instance-state-name,Values=running,pending,stopped,stopping" --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null)

if [ -n "$ORIG_INSTANCE_ID" ] && [ "$ORIG_INSTANCE_ID" != "None" ]; then
  aws ec2 terminate-instances --instance-ids "${ORIG_INSTANCE_ID}" >> ~/tmp/terminate-logs.txt 2>&1
  echo "✅ Terminated ${EC2INSTANCE} (${ORIG_INSTANCE_ID})"
else
  echo "ℹ️ Original instance ${EC2INSTANCE} not found"
fi

# Wait for all instances to terminate
echo "⏳ Waiting for all instances to terminate..."
for AZ_COPY in "${AZS_COPY[@]}"; do
  INSTANCE_NAME="${EC2INSTANCE}-copy-${AZ_COPY}"
  INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${INSTANCE_NAME}" "Name=instance-state-name,Values=shutting-down,running,stopping,stopped" --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null)
  if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "None" ]; then
    aws ec2 wait instance-terminated --instance-ids "${INSTANCE_ID}"
  fi
done

if [ -n "$ORIG_INSTANCE_ID" ] && [ "$ORIG_INSTANCE_ID" != "None" ]; then
  aws ec2 wait instance-terminated --instance-ids "${ORIG_INSTANCE_ID}"
fi
echo "✅ All instances terminated"

# Delete volumes
echo "💾 Deleting volumes..."
for AZ_COPY in "${AZS_COPY[@]}"; do
  VOLUME_NAME="${EC2INSTANCE}-volume-${AZ_COPY}"
  VOLUME_ID=$(aws ec2 describe-volumes --filters "Name=tag:Name,Values=${VOLUME_NAME}" --query 'Volumes[0].VolumeId' --output text 2>/dev/null)
  
  if [ -n "$VOLUME_ID" ] && [ "$VOLUME_ID" != "None" ]; then
    aws ec2 delete-volume --volume-id "${VOLUME_ID}" >> ~/tmp/terminate-logs.txt 2>&1
    echo "✅ Deleted volume ${VOLUME_NAME} (${VOLUME_ID})"
  else
    echo "ℹ️ Volume ${VOLUME_NAME} not found"
  fi
done

# Delete snapshots
echo "📸 Deleting snapshots..."
SNAPSHOT_NAME="${EC2INSTANCE}-snapshot"
SNAPSHOT_ID=$(aws ec2 describe-snapshots --filters "Name=tag:Name,Values=${SNAPSHOT_NAME}" --owner-ids self --query 'Snapshots[0].SnapshotId' --output text 2>/dev/null)

if [ -n "$SNAPSHOT_ID" ] && [ "$SNAPSHOT_ID" != "None" ]; then
  aws ec2 delete-snapshot --snapshot-id "${SNAPSHOT_ID}" >> ~/tmp/terminate-logs.txt 2>&1
  echo "✅ Deleted snapshot ${SNAPSHOT_NAME} (${SNAPSHOT_ID})"
else
  echo "ℹ️ Snapshot ${SNAPSHOT_NAME} not found"
fi

# Delete security group
echo "🔒 Deleting security group ${SECURITYGROUP}..."
SECURITYGROUP_ID=$(aws ec2 describe-security-groups --group-names "${SECURITYGROUP}" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)

if [ -n "$SECURITYGROUP_ID" ] && [ "$SECURITYGROUP_ID" != "None" ]; then
  aws ec2 delete-security-group --group-id "${SECURITYGROUP_ID}" >> ~/tmp/terminate-logs.txt 2>&1
  echo "✅ Deleted security group ${SECURITYGROUP} (${SECURITYGROUP_ID})"
else
  echo "ℹ️ Security group ${SECURITYGROUP} not found"
fi

echo "
🎉 Cleanup completed successfully!"