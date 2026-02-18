#!/bin/bash

BUCKET_PREFIX="${1}"
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

# Disable Block Public Access settings
echo "🔓 Disabling Block Public Access..."
aws s3api put-public-access-block \
  --bucket ${S3_WEB_HOST_BUCKET} \
  --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"
echo "✅ Block Public Access disabled"

# Configure bucket for static website hosting
echo "🌐 Configuring static website hosting..."
aws s3 website s3://${S3_WEB_HOST_BUCKET}/ --index-document index.html --error-document error.html
echo "✅ Static website hosting configured"

# Set bucket policy for public read access
echo "🔓 Setting bucket policy for public access..."
cat > /tmp/bucket-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${S3_WEB_HOST_BUCKET}/*"
    }
  ]
}
EOF

aws s3api put-bucket-policy --bucket ${S3_WEB_HOST_BUCKET} --policy file:///tmp/bucket-policy.json
rm -f /tmp/bucket-policy.json
echo "✅ Bucket policy set"

# Upload website files
echo "📤 Uploading website files..."
aws s3 sync ./06-StaticWebs/01-FirstPractice/ s3://${S3_WEB_HOST_BUCKET}/ --delete
echo "✅ Files uploaded"

# Get website URL
REGION=$(aws configure get region)
if [ -z "$REGION" ]; then
  REGION="us-east-1"
fi

WEBSITE_URL="http://${S3_WEB_HOST_BUCKET}.s3-website-${REGION}.amazonaws.com"

echo "
🎉 Static website hosting setup complete!"
echo "Website URL: ${WEBSITE_URL}"
echo "Bucket: ${S3_WEB_HOST_BUCKET}"
echo "Versioning: Enabled"