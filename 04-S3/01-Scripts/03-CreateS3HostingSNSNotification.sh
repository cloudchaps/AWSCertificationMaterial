#!/bin/bash

BUCKET_PREFIX="${1}"
CLOUDFRONT_DISTRO="${2}"
SNS_TOPIC="${3}"
EMAIL_TOPIC_SUB="${4}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
S3_WEB_HOST_BUCKET="${BUCKET_PREFIX}-${TIMESTAMP}"

# Create S3 bucket
echo "📦 Creating S3 bucket ${S3_WEB_HOST_BUCKET}..."
aws s3 mb s3://${S3_WEB_HOST_BUCKET}
echo "✅ Bucket created"

# Enable versioning
echo "🔄 Enabling versioning..."
aws s3api put-bucket-versioning --bucket ${S3_WEB_HOST_BUCKET} --versioning-configuration Status=Enabled
echo "✅ Versioning enabled"

# Keep bucket private (no public access block changes)
echo "🔒 Keeping bucket private for CloudFront access..."

# Upload website files
echo "📤 Uploading website files..."
aws s3 sync ./06-StaticWebs/02-SecondPractice/ s3://${S3_WEB_HOST_BUCKET}/ --delete
echo "✅ Files uploaded"

# Create CloudFront Origin Access Identity (OAI)
echo "🔑 Creating CloudFront Origin Access Identity..."
OAI_RESPONSE=$(aws cloudfront create-cloud-front-origin-access-identity \
  --cloud-front-origin-access-identity-config \
    CallerReference="${CLOUDFRONT_DISTRO}-$(date +%s)",Comment="OAI for ${S3_WEB_HOST_BUCKET}" \
  --output json)

OAI_ID=$(echo $OAI_RESPONSE | jq -r '.CloudFrontOriginAccessIdentity.Id')
OAI_CANONICAL_USER=$(echo $OAI_RESPONSE | jq -r '.CloudFrontOriginAccessIdentity.S3CanonicalUserId')
echo "✅ Created OAI: ${OAI_ID}"
echo "   Canonical User: ${OAI_CANONICAL_USER}"

# Set bucket policy to allow CloudFront OAI access
echo "🔓 Setting bucket policy for CloudFront access..."
cat > /tmp/bucket-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CloudFrontReadGetObject",
      "Effect": "Allow",
      "Principal": {
        "CanonicalUser": "${OAI_CANONICAL_USER}"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${S3_WEB_HOST_BUCKET}/*"
    }
  ]
}
EOF

aws s3api put-bucket-policy --bucket ${S3_WEB_HOST_BUCKET} --policy file:///tmp/bucket-policy.json
rm -f /tmp/bucket-policy.json
echo "✅ Bucket policy set for CloudFront"

# Create CloudFront distribution
echo "☁️ Creating CloudFront distribution..."
cat > /tmp/distro-config.json <<EOF
{
  "CallerReference": "${CLOUDFRONT_DISTRO}-$(date +%s)",
  "Comment": "${CLOUDFRONT_DISTRO}",
  "Enabled": true,
  "DefaultRootObject": "index.html",
  "Origins": {
    "Quantity": 1,
    "Items": [
      {
        "Id": "S3-${S3_WEB_HOST_BUCKET}",
        "DomainName": "${S3_WEB_HOST_BUCKET}.s3.amazonaws.com",
        "S3OriginConfig": {
          "OriginAccessIdentity": "origin-access-identity/cloudfront/${OAI_ID}"
        }
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "S3-${S3_WEB_HOST_BUCKET}",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["GET", "HEAD"],
      "CachedMethods": {
        "Quantity": 2,
        "Items": ["GET", "HEAD"]
      }
    },
    "ForwardedValues": {
      "QueryString": false,
      "Cookies": {
        "Forward": "none"
      }
    },
    "MinTTL": 0,
    "Compress": true
  }
}
EOF

DISTRO_ID=$(aws cloudfront create-distribution --distribution-config file:///tmp/distro-config.json --query 'Distribution.Id' --output text)
DISTRO_DOMAIN=$(aws cloudfront get-distribution --id ${DISTRO_ID} --query 'Distribution.DomainName' --output text)
rm -f /tmp/distro-config.json
echo "✅ Created CloudFront distribution: ${DISTRO_ID}"

# Create SNS Topic
echo "📬 Creating SNS topic ${SNS_TOPIC}..."
TOPIC_ARN=$(aws sns create-topic --name "${SNS_TOPIC}" --query 'TopicArn' --output text)
echo "✅ Created SNS topic: ${TOPIC_ARN}"

# Subscribe email to SNS topic
echo "📧 Subscribing ${EMAIL_TOPIC_SUB} to SNS topic..."
SUBSCRIPTION_ARN=$(aws sns subscribe \
  --topic-arn "${TOPIC_ARN}" \
  --protocol email \
  --notification-endpoint "${EMAIL_TOPIC_SUB}" \
  --query 'SubscriptionArn' --output text)
echo "✅ Email subscription created (pending confirmation)"
echo "   Check ${EMAIL_TOPIC_SUB} inbox and confirm subscription"

# Configure S3 bucket notification to SNS
echo "🔔 Configuring S3 event notifications..."
cat > /tmp/notification-config.json <<EOF
{
  "TopicConfigurations": [
    {
      "Id": "S3ObjectCreatedEvent",
      "TopicArn": "${TOPIC_ARN}",
      "Events": ["s3:ObjectCreated:*"]
    }
  ]
}
EOF

# Add SNS publish permission to bucket
echo "🔓 Adding SNS publish permission to topic..."
aws sns set-topic-attributes \
  --topic-arn "${TOPIC_ARN}" \
  --attribute-name Policy \
  --attribute-value '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "s3.amazonaws.com"
        },
        "Action": "SNS:Publish",
        "Resource": "'"${TOPIC_ARN}"'",
        "Condition": {
          "ArnLike": {
            "aws:SourceArn": "arn:aws:s3:::'"${S3_WEB_HOST_BUCKET}"'"
          }
        }
      }
    ]
  }'

aws s3api put-bucket-notification-configuration \
  --bucket "${S3_WEB_HOST_BUCKET}" \
  --notification-configuration file:///tmp/notification-config.json
rm -f /tmp/notification-config.json
echo "✅ S3 event notifications configured"

# Get website URL
REGION=$(aws configure get region)
if [ -z "$REGION" ]; then
  REGION="us-east-1"
fi

WEBSITE_URL="http://${S3_WEB_HOST_BUCKET}.s3-website-${REGION}.amazonaws.com"

echo "
🎉 Private S3 bucket with CloudFront and SNS setup complete!"
echo "CloudFront URL: https://${DISTRO_DOMAIN}"
echo "CloudFront Distribution ID: ${DISTRO_ID}"
echo "S3 Bucket: ${S3_WEB_HOST_BUCKET} (Private)"
echo "SNS Topic: ${TOPIC_ARN}"
echo "Email Subscription: ${EMAIL_TOPIC_SUB} (pending confirmation)"
echo "Versioning: Enabled"
echo "
Note: "
echo "- CloudFront distribution may take 15-20 minutes to deploy globally."
echo "- Check ${EMAIL_TOPIC_SUB} and confirm the SNS subscription."
echo "- Upload a file to test: aws s3 cp test.txt s3://${S3_WEB_HOST_BUCKET}/"