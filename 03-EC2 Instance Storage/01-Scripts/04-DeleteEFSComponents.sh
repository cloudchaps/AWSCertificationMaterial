#!/bin/bash

VPCID="${1}"
EC2INSTANCE_PREFIX="${2}"
SECURITYGROUP="${3}"
shift 3
AZS_COPY=("$@") # Array of AZ names

# Terminate all instances
INSTANCE_COUNT=0
for AZ_COPY in "${AZS_COPY[@]}"; do
  INSTANCE_COUNT=$((INSTANCE_COUNT + 1))
  INSTANCE_NAME="${EC2INSTANCE_PREFIX}-${INSTANCE_COUNT}"
  
  echo "🗑️ Terminating instance ${INSTANCE_NAME}..."
  INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${INSTANCE_NAME}" "Name=instance-state-name,Values=running,pending,stopped,stopping" --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null)
  
  if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "None" ]; then
    aws ec2 terminate-instances --instance-ids "${INSTANCE_ID}" >> ~/tmp/terminate-logs.txt 2>&1
    echo "✅ Terminated ${INSTANCE_NAME} (${INSTANCE_ID})"
  else
    echo "ℹ️ Instance ${INSTANCE_NAME} not found"
  fi
done

# Wait for all instances to terminate
echo "⏳ Waiting for all instances to terminate..."
INSTANCE_COUNT=0
for AZ_COPY in "${AZS_COPY[@]}"; do
  INSTANCE_COUNT=$((INSTANCE_COUNT + 1))
  INSTANCE_NAME="${EC2INSTANCE_PREFIX}-${INSTANCE_COUNT}"
  INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${INSTANCE_NAME}" "Name=instance-state-name,Values=shutting-down,running,stopping,stopped" --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null)
  if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "None" ]; then
    aws ec2 wait instance-terminated --instance-ids "${INSTANCE_ID}"
  fi
done
echo "✅ All instances terminated"

# Get EFS ID
echo "💾 Getting EFS filesystem ID..."
EFS_ID=$(aws efs describe-file-systems --query "FileSystems[?Tags[?Key=='Name' && Value=='${EC2INSTANCE_PREFIX}-efs']].FileSystemId" --output text)

if [ -n "$EFS_ID" ] && [ "$EFS_ID" != "None" ]; then
  echo "✅ Found EFS: ${EFS_ID}"
  
  # Delete mount targets
  echo "🔗 Deleting EFS mount targets..."
  MOUNT_TARGET_IDS=$(aws efs describe-mount-targets --file-system-id "${EFS_ID}" --query 'MountTargets[*].MountTargetId' --output text)
  
  for MOUNT_TARGET_ID in $MOUNT_TARGET_IDS; do
    echo "Deleting mount target: ${MOUNT_TARGET_ID}"
    aws efs delete-mount-target --mount-target-id "${MOUNT_TARGET_ID}" >> ~/tmp/terminate-logs.txt 2>&1
  done
  
  # Wait for mount targets to be deleted
  echo "⏳ Waiting for mount targets to be deleted (30 seconds)..."
  sleep 30
  echo "✅ Mount targets deleted"
  
  # Delete EFS filesystem
  echo "💾 Deleting EFS filesystem ${EFS_ID}..."
  aws efs delete-file-system --file-system-id "${EFS_ID}" >> ~/tmp/terminate-logs.txt 2>&1
  echo "✅ Deleted EFS filesystem"
else
  echo "ℹ️ EFS filesystem ${EC2INSTANCE_PREFIX}-efs not found"
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

echo "\n🎉 Cleanup completed successfully!"