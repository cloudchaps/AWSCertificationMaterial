#!/bin/bash

BUCKET_PREFIX="${1}"
CLOUDFRONT_DISTRO="${2}"
SNS_TOPIC="${3}"

# Delete S3 buckets with prefix
echo "📦 Deleting S3 buckets with prefix ${BUCKET_PREFIX}..."
BUCKETS=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, '${BUCKET_PREFIX}')].Name" --output text)

for BUCKET in $BUCKETS; do
  echo "Deleting bucket: ${BUCKET}"
  
  # Remove all objects and versions
  aws s3 rm s3://${BUCKET} --recursive >> ~/tmp/cleanup-logs.txt 2>&1
  
  # Delete all object versions if versioning is enabled
  aws s3api delete-objects --bucket ${BUCKET} \
    --delete "$(aws s3api list-object-versions --bucket ${BUCKET} \
    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json)" \
    >> ~/tmp/cleanup-logs.txt 2>&1
  
  # Delete all delete markers
  aws s3api delete-objects --bucket ${BUCKET} \
    --delete "$(aws s3api list-object-versions --bucket ${BUCKET} \
    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json)" \
    >> ~/tmp/cleanup-logs.txt 2>&1
  
  # Delete bucket
  aws s3 rb s3://${BUCKET} --force >> ~/tmp/cleanup-logs.txt 2>&1
  echo "✅ Deleted bucket: ${BUCKET}"
done

if [ -z "$BUCKETS" ]; then
  echo "ℹ️ No buckets found with prefix ${BUCKET_PREFIX}"
fi

# Disable and delete CloudFront distribution
echo "☁️ Disabling CloudFront distribution..."
DISTRO_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Comment=='${CLOUDFRONT_DISTRO}'].Id" --output text)

if [ -n "$DISTRO_ID" ] && [ "$DISTRO_ID" != "None" ]; then
  echo "Found distribution: ${DISTRO_ID}"
  
  # Get current config and ETag
  DISTRO_CONFIG=$(aws cloudfront get-distribution-config --id ${DISTRO_ID})
  ETAG=$(echo $DISTRO_CONFIG | jq -r '.ETag')
  
  # Disable distribution
  echo $DISTRO_CONFIG | jq '.DistributionConfig.Enabled = false | .DistributionConfig' > /tmp/distro-config.json
  aws cloudfront update-distribution --id ${DISTRO_ID} \
    --distribution-config file:///tmp/distro-config.json \
    --if-match ${ETAG} >> ~/tmp/cleanup-logs.txt 2>&1
  rm -f /tmp/distro-config.json
  
  echo "⏳ Waiting for distribution to be disabled (this may take 15-20 minutes)..."
  aws cloudfront wait distribution-deployed --id ${DISTRO_ID}
  
  # Get new ETag after disable
  NEW_ETAG=$(aws cloudfront get-distribution --id ${DISTRO_ID} --query 'ETag' --output text)
  
  # Delete distribution
  echo "🗑️ Deleting CloudFront distribution..."
  aws cloudfront delete-distribution --id ${DISTRO_ID} --if-match ${NEW_ETAG} >> ~/tmp/cleanup-logs.txt 2>&1
  echo "✅ Deleted CloudFront distribution: ${DISTRO_ID}"
else
  echo "ℹ️ CloudFront distribution ${CLOUDFRONT_DISTRO} not found"
fi

# Delete SNS topic and subscriptions
echo "📬 Deleting SNS topic ${SNS_TOPIC}..."
TOPIC_ARN=$(aws sns list-topics --query "Topics[?contains(TopicArn, '${SNS_TOPIC}')].TopicArn" --output text)

if [ -n "$TOPIC_ARN" ] && [ "$TOPIC_ARN" != "None" ]; then
  echo "Found topic: ${TOPIC_ARN}"
  
  # Delete all subscriptions
  SUBSCRIPTIONS=$(aws sns list-subscriptions-by-topic --topic-arn "${TOPIC_ARN}" \
    --query 'Subscriptions[].SubscriptionArn' --output text)
  
  for SUB_ARN in $SUBSCRIPTIONS; do
    if [ "$SUB_ARN" != "PendingConfirmation" ]; then
      aws sns unsubscribe --subscription-arn "${SUB_ARN}" >> ~/tmp/cleanup-logs.txt 2>&1
      echo "Deleted subscription: ${SUB_ARN}"
    fi
  done
  
  # Delete topic
  aws sns delete-topic --topic-arn "${TOPIC_ARN}" >> ~/tmp/cleanup-logs.txt 2>&1
  echo "✅ Deleted SNS topic: ${TOPIC_ARN}"
else
  echo "ℹ️ SNS topic ${SNS_TOPIC} not found"
fi

echo "\n🎉 Cleanup completed successfully!"