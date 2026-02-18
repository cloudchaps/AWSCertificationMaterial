#!/bin/bash

EC2INSTANCES=("$@") # Array of instance names

# Loop through each instance name
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