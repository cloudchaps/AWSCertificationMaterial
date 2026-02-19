#!/bin/bash

VPCID="vpc-0e445e8482559fb54"
AZ="us-east-1d"
AMI_ID="ami-0b6c6ebed2801a5cb"  # Amazon Linux 2 AMI
INSTANCE_NAME="CloudChamps - CRUD Main"
SECURITYGROUP="${1:-crud-security-group}"
DB_SECURITYGROUP="crud-db-security-group"
MEMCACHE_SECURITYGROUP="crud-memcache-security-group"
DB_NAME="${2:-cruddb}"
DB_USER="${3:-admin}"
DB_PASS="${4:-CloudChaps2024!}"
HOSTED_ZONE_ID="${5}"
DOMAIN_NAME="${6}"
S3_BUCKET_NAME="crud-images-$(date +%s)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGES_DIR="${SCRIPT_DIR}/../07-Images"

# Create EC2 security group
echo "🔍 Checking EC2 security group ${SECURITYGROUP}..."
SECURITYGROUP_ID=$(aws ec2 describe-security-groups --group-names ${SECURITYGROUP} --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)

if [ -z "$SECURITYGROUP_ID" ] || [ "$SECURITYGROUP_ID" = "None" ]; then
  echo "📦 Creating EC2 security group..."
  SECURITYGROUP_ID=$(aws ec2 create-security-group \
    --group-name "${SECURITYGROUP}" \
    --description "Security group for CRUD application" \
    --vpc-id "${VPCID}" \
    --query 'GroupId' --output text 2>/dev/null) 
  
  aws ec2 authorize-security-group-ingress \
    --group-id "${SECURITYGROUP_ID}" \
    --ip-permissions \
      IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges='[{CidrIp=0.0.0.0/0}]' \
      IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges='[{CidrIp=0.0.0.0/0}]' >/dev/null 2>&1
  
  echo "✅ Created EC2 security group: ${SECURITYGROUP_ID}"
else
  echo "✅ EC2 security group found: ${SECURITYGROUP_ID}"
fi

# Create DB security group
echo "🔍 Checking DB security group ${DB_SECURITYGROUP}..."
DB_SECURITYGROUP_ID=$(aws ec2 describe-security-groups --group-names ${DB_SECURITYGROUP} --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)

if [ -z "$DB_SECURITYGROUP_ID" ] || [ "$DB_SECURITYGROUP_ID" = "None" ]; then
  echo "📦 Creating DB security group..."
  DB_SECURITYGROUP_ID=$(aws ec2 create-security-group \
    --group-name "${DB_SECURITYGROUP}" \
    --description "Security group for RDS database" \
    --vpc-id "${VPCID}" \
    --query 'GroupId' --output text 2>/dev/null)
  
  aws ec2 authorize-security-group-ingress \
    --group-id "${DB_SECURITYGROUP_ID}" \
    --protocol tcp \
    --port 3306 \
    --source-group "${SECURITYGROUP_ID}" >/dev/null 2>&1
  
  echo "✅ Created DB security group: ${DB_SECURITYGROUP_ID}"
else
  echo "✅ DB security group found: ${DB_SECURITYGROUP_ID}"
fi

# Create Memcache security group
echo "🔍 Checking Memcache security group ${MEMCACHE_SECURITYGROUP}..."
MEMCACHE_SECURITYGROUP_ID=$(aws ec2 describe-security-groups --group-names ${MEMCACHE_SECURITYGROUP} --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)

if [ -z "$MEMCACHE_SECURITYGROUP_ID" ] || [ "$MEMCACHE_SECURITYGROUP_ID" = "None" ]; then
  echo "📦 Creating Memcache security group..."
  MEMCACHE_SECURITYGROUP_ID=$(aws ec2 create-security-group \
    --group-name "${MEMCACHE_SECURITYGROUP}" \
    --description "Security group for Memcached" \
    --vpc-id "${VPCID}" \
    --query 'GroupId' --output text 2>/dev/null)
  
  aws ec2 authorize-security-group-ingress \
    --group-id "${MEMCACHE_SECURITYGROUP_ID}" \
    --protocol tcp \
    --port 11211 \
    --source-group "${SECURITYGROUP_ID}" >/dev/null 2>&1
  
  echo "✅ Created Memcache security group: ${MEMCACHE_SECURITYGROUP_ID}"
else
  echo "✅ Memcache security group found: ${MEMCACHE_SECURITYGROUP_ID}"
fi

# Get subnet in the specified AZ
echo "🔍 Getting subnet in AZ ${AZ}..."
SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPCID}" "Name=availability-zone,Values=${AZ}" --query 'Subnets[0].SubnetId' --output text)
if [ -z "$SUBNET_ID" ] || [ "$SUBNET_ID" = "None" ]; then
  echo "❌ No subnet found in AZ ${AZ}!"
  exit 1
fi
echo "✅ Found subnet: ${SUBNET_ID}"

# Get all subnets in VPC (need at least 2 for serverless cache)
SUBNET_IDS_ARRAY=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPCID}" --query 'Subnets[*].SubnetId' --output text)
SUBNET_COUNT=$(echo $SUBNET_IDS_ARRAY | wc -w)

if [ $SUBNET_COUNT -lt 2 ]; then
  echo "❌ Need at least 2 subnets for serverless cache. Found: $SUBNET_COUNT"
  exit 1
fi

# Get first 2-3 subnets for cache
SUBNET_IDS=$(echo $SUBNET_IDS_ARRAY | awk '{for(i=1;i<=3 && i<=NF;i++) printf "%s ", $i}')
SUBNET_IDS=$(echo $SUBNET_IDS | xargs)
echo "✅ Found subnets for cache: ${SUBNET_IDS}"

# All subnets for RDS
ALL_SUBNET_IDS=$(echo $SUBNET_IDS_ARRAY | tr '\t' ' ')

# Create cache subnet group
echo "⚡ Creating cache subnet group..."
aws elasticache create-cache-subnet-group \
  --cache-subnet-group-name crud-cache-subnet-group \
  --cache-subnet-group-description "Subnet group for Memcached" \
  --subnet-ids $ALL_SUBNET_IDS 2>/dev/null || echo "Cache subnet group already exists"

# Create Memcached serverless cache
echo "⚡ Creating Memcached serverless cache..."
CACHE_NAME="crud-memcached"
SUBNET_MEMCACHED_IDS="subnet-0c9ff28330e54b689 subnet-0fdcdc7bb859c610e"
aws elasticache create-serverless-cache \
  --serverless-cache-name ${CACHE_NAME} \
  --engine memcached \
  --security-group-ids ${MEMCACHE_SECURITYGROUP_ID} \
  --subnet-ids ${SUBNET_MEMCACHED_IDS} 2>/dev/null

if [ $? -eq 0 ]; then
  echo "✅ Memcached serverless cache creation initiated"
  echo "⏳ Waiting for cache to be available..."
  sleep 60
  echo "✅ Memcached cache is being created"
else
  echo "❌ Memcached cache already exists. Continuing..."
  #exit 1
fi

# Get Memcached endpoint
MEMCACHE_ENDPOINT=$(aws elasticache describe-serverless-caches --serverless-cache-name ${CACHE_NAME} --query 'ServerlessCaches[0].Endpoint.Address' --output text 2>/dev/null)
if [ -z "$MEMCACHE_ENDPOINT" ] || [ "$MEMCACHE_ENDPOINT" = "None" ]; then
  echo "⚠️ Memcached endpoint not yet available, will be set in environment"
  MEMCACHE_ENDPOINT="pending"
else
  echo "✅ Memcached Endpoint: ${MEMCACHE_ENDPOINT}"
fi

# Create DB subnet group
echo "🗄️ Creating DB subnet group..."
aws rds create-db-subnet-group \
  --db-subnet-group-name crud-db-subnet-group \
  --db-subnet-group-description "Subnet group for CRUD RDS" \
  --subnet-ids $ALL_SUBNET_IDS 2>/dev/null || echo "DB subnet group already exists"

# Create RDS MySQL instance
echo "🗄️ Creating RDS MySQL instance... and this DB ${DB_NAME}"
DB_INSTANCE_ID="crud-mysql-db"
aws rds create-db-instance \
  --db-instance-identifier ${DB_INSTANCE_ID} \
  --db-instance-class db.t3.micro \
  --engine mysql \
  --master-username ${DB_USER} \
  --master-user-password ${DB_PASS} \
  --allocated-storage 20 \
  --db-name ${DB_NAME} \
  --vpc-security-group-ids ${DB_SECURITYGROUP_ID} \
  --db-subnet-group-name crud-db-subnet-group \
  --publicly-accessible \
  --no-multi-az \
  --storage-type gp2 \
  --backup-retention-period 0 \
  --no-deletion-protection 

if [ $? -eq 0 ]; then
  echo "✅ RDS instance creation initiated"
  echo "⏳ Waiting for RDS instance to be available (this may take 5-10 minutes)..."
  aws rds wait db-instance-available --db-instance-identifier ${DB_INSTANCE_ID}
  echo "✅ RDS instance is available"
else
  echo "❌ RDS instance already exists. Exiting..."
  exit 1
fi

# Get RDS endpoint
DB_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier ${DB_INSTANCE_ID} --query 'DBInstances[0].Endpoint.Address' --output text)
echo "✅ RDS Endpoint: ${DB_ENDPOINT}"

# Create S3 bucket for images
echo "📦 Creating S3 bucket: ${S3_BUCKET_NAME}..."
REGION=$(aws configure get region)
aws s3api create-bucket --bucket ${S3_BUCKET_NAME} --region ${REGION} >/dev/null 2>&1
echo "✅ S3 bucket created"

# Disable block public access
echo "🔓 Configuring S3 bucket public access..."
aws s3api put-public-access-block \
  --bucket ${S3_BUCKET_NAME} \
  --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false" >/dev/null 2>&1

# Apply bucket policy
echo "📝 Applying S3 bucket policy..."
cat > /tmp/bucket-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}/*"
    }
  ]
}
EOF
aws s3api put-bucket-policy --bucket ${S3_BUCKET_NAME} --policy file:///tmp/bucket-policy.json >/dev/null 2>&1

# Apply CORS policy
echo "🌐 Applying CORS policy..."
cat > /tmp/cors-policy.json <<EOF
[
  {
    "AllowedHeaders": ["*"],
    "AllowedMethods": ["GET", "HEAD"],
    "AllowedOrigins": ["*"],
    "ExposeHeaders": ["ETag"],
    "MaxAgeSeconds": 3000
  }
]
EOF
aws s3api put-bucket-cors --bucket ${S3_BUCKET_NAME} --cors-configuration file:///tmp/cors-policy.json >/dev/null 2>&1
echo "✅ S3 bucket configured"

# Upload images to S3
echo "📤 Uploading images to S3..."
if [ -d "${IMAGES_DIR}" ]; then
  for img in "${IMAGES_DIR}"/*; do
    if [ -f "$img" ]; then
      aws s3 cp "$img" "s3://${S3_BUCKET_NAME}/" >/dev/null 2>&1
      echo "  ✅ Uploaded $(basename "$img")"
    fi
  done
else
  echo "  ⚠️ Images directory not found: ${IMAGES_DIR}"
fi

# Get first image S3 URI for database
FIRST_IMAGE=$(aws s3 ls s3://${S3_BUCKET_NAME}/ | head -1 | awk '{print $4}')
IMAGE_S3_URI="https://${S3_BUCKET_NAME}.s3.${REGION}.amazonaws.com/${FIRST_IMAGE}"
echo "✅ Sample image URI: ${IMAGE_S3_URI}"

# Create user-data script
cat > /tmp/userdata.sh <<'USERDATA'
#!/bin/bash
exec > >(tee /var/log/user-data.log)
exec 2>&1

# Install PHP and MySQL client for Ubuntu
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y php libapache2-mod-php php-mysql php-memcached apache2 mysql-client

# Download index.php from GitHub
cd /var/www/html
curl -o index.php https://raw.githubusercontent.com/cloudchaps/AWSCertificationMaterial/refs/heads/dev1/06-Route53/06-CRUDService/index.php

# Set proper permissions
chown -R www-data:www-data /var/www/html/
chmod -R 755 /var/www/html/

# Set DB environment variables
cat > /etc/apache2/conf-available/db-env.conf <<ENVEOF
SetEnv DB_HOST "DB_ENDPOINT_PLACEHOLDER"
SetEnv DB_NAME "DB_NAME_PLACEHOLDER"
SetEnv DB_USER "DB_USER_PLACEHOLDER"
SetEnv DB_PASS "DB_PASS_PLACEHOLDER"
SetEnv MEMCACHE_HOST "MEMCACHE_ENDPOINT_PLACEHOLDER"
ENVEOF

a2enconf db-env
systemctl restart apache2

# Wait for RDS to be ready
sleep 30

# Initialize database
mysql -h DB_ENDPOINT_PLACEHOLDER -u DB_USER_PLACEHOLDER -pDB_PASS_PLACEHOLDER <<SQL
CREATE DATABASE IF NOT EXISTS DB_NAME_PLACEHOLDER;
USE DB_NAME_PLACEHOLDER;
CREATE TABLE IF NOT EXISTS items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    s3_uri VARCHAR(500),
    item_arn VARCHAR(500),
    etag VARCHAR(100),
    valid_service boolean,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
INSERT INTO items (name, description, s3_uri, item_arn, etag, valid_service) VALUES
('EC2', 'Web service that provides sizable compute capacity in the cloud.', 'IMAGE_S3_URI_PLACEHOLDER', 'arn:aws:s3:::BUCKET_NAME_PLACEHOLDER/image1.png', 'sample-etag-1', 1),
('Memcache', 'Is a free, open-source, high-performance, distributed memory object caching system.', 'IMAGE_S3_URI_PLACEHOLDER', 'arn:aws:s3:::BUCKET_NAME_PLACEHOLDER/image2.png', 'sample-etag-2', 1),
('Route53', 'is a highly available and scalable cloud Domain Name System (DNS) web service designed to route end-users to internet applications by translating human-readable names.', 'IMAGE_S3_URI_PLACEHOLDER', 'arn:aws:s3:::BUCKET_NAME_PLACEHOLDER/image3.png', 'sample-etag-3', 1),
('RDS', 'Is a managed relational database service for MySQL, PostgreSQL, MariaDB, Oracle, or SQL Server.', 'IMAGE_S3_URI_PLACEHOLDER', 'arn:aws:s3:::BUCKET_NAME_PLACEHOLDER/image4.png', 'sample-etag-4', 1);
SQL
USERDATA

# Replace placeholders in user-data
sed -i "s/DB_ENDPOINT_PLACEHOLDER/${DB_ENDPOINT}/g" /tmp/userdata.sh
sed -i "s/DB_NAME_PLACEHOLDER/${DB_NAME}/g" /tmp/userdata.sh
sed -i "s/DB_USER_PLACEHOLDER/${DB_USER}/g" /tmp/userdata.sh
sed -i "s/DB_PASS_PLACEHOLDER/${DB_PASS}/g" /tmp/userdata.sh
sed -i "s/MEMCACHE_ENDPOINT_PLACEHOLDER/${MEMCACHE_ENDPOINT}/g" /tmp/userdata.sh
sed -i "s|IMAGE_S3_URI_PLACEHOLDER|${IMAGE_S3_URI}|g" /tmp/userdata.sh
sed -i "s/BUCKET_NAME_PLACEHOLDER/${S3_BUCKET_NAME}/g" /tmp/userdata.sh

# Launch EC2 instance
echo "🚀 Launching EC2 instance..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id ${AMI_ID} \
  --instance-type t2.micro \
  --subnet-id ${SUBNET_ID} \
  --security-group-ids ${SECURITYGROUP_ID} \
  --associate-public-ip-address \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":8,"VolumeType":"gp2"}}]' \
  --user-data file:///tmp/userdata.sh \
  --query 'Instances[0].InstanceId' --output text)

aws ec2 create-tags --resources ${INSTANCE_ID} --tags Key=Name,Value="${INSTANCE_NAME}" >/dev/null 2>&1
echo "✅ Launched EC2 instance: ${INSTANCE_ID}"

# Wait for instance to be running
echo "⏳ Waiting for instance to be running..."
aws ec2 wait instance-running --instance-ids ${INSTANCE_ID}
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids ${INSTANCE_ID} --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

# Allocate Elastic IP
echo "🌐 Allocating Elastic IP..."
ALLOCATION_ID=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)
ELASTIC_IP=$(aws ec2 describe-addresses --allocation-ids ${ALLOCATION_ID} --query 'Addresses[0].PublicIp' --output text)
echo "✅ Elastic IP allocated: ${ELASTIC_IP}"

# Associate Elastic IP with instance
echo "🔗 Associating Elastic IP with instance..."
aws ec2 associate-address --instance-id ${INSTANCE_ID} --allocation-id ${ALLOCATION_ID} >/dev/null 2>&1
echo "✅ Elastic IP associated"

# Create Route53 record
if [ ! -z "${HOSTED_ZONE_ID}" ] && [ ! -z "${DOMAIN_NAME}" ]; then
  echo "🌍 Creating Route53 DNS record..."
  cat > /tmp/route53-change.json <<EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${DOMAIN_NAME}",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [
          {
            "Value": "${ELASTIC_IP}"
          }
        ]
      }
    }
  ]
}
EOF
  aws route53 change-resource-record-sets \
    --hosted-zone-id ${HOSTED_ZONE_ID} \
    --change-batch file:///tmp/route53-change.json >/dev/null 2>&1
  echo "✅ Route53 record created: ${DOMAIN_NAME} -> ${ELASTIC_IP}"
  rm -f /tmp/route53-change.json
else
  echo "ℹ️ Skipping Route53 record (HOSTED_ZONE_ID or DOMAIN_NAME not provided)"
fi

echo "📝 Check user-data execution: ssh ec2-user@${PUBLIC_IP} 'sudo cat /var/log/cloud-init-output.log'"

# Clean up
rm -f /tmp/userdata.sh /tmp/bucket-policy.json /tmp/cors-policy.json

echo "
🎉 Deployment complete!

📋 Resources Created:
- RDS Instance: ${DB_INSTANCE_ID}
- RDS Endpoint: ${DB_ENDPOINT}
- Memcached Cache: ${CACHE_NAME}
- Memcached Endpoint: ${MEMCACHE_ENDPOINT}
- S3 Bucket: ${S3_BUCKET_NAME}
- EC2 Instance: ${INSTANCE_ID}
- Instance Name: ${INSTANCE_NAME}
- Elastic IP: ${ELASTIC_IP}
- Allocation ID: ${ALLOCATION_ID}
${DOMAIN_NAME:+- Domain: ${DOMAIN_NAME}}

🌐 Access your CRUD application:
   http://${ELASTIC_IP}/index.php
${DOMAIN_NAME:+   http://${DOMAIN_NAME}/index.php}

📝 Database Credentials:
   Host: ${DB_ENDPOINT}
   Database: ${DB_NAME}
   Username: ${DB_USER}
   Password: ${DB_PASS}

⚡ Memcached:
   Endpoint: ${MEMCACHE_ENDPOINT}

📦 S3 Bucket:
   Name: ${S3_BUCKET_NAME}
   Sample Image: ${IMAGE_S3_URI}

Note: Wait 2-3 minutes for user-data script to complete setup.
"
