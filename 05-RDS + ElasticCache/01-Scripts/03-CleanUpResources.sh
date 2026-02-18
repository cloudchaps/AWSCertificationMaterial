#!/bin/bash

INSTANCE_NAME="CloudChamps - CRUD Main"
SECURITYGROUP="${1:-crud-security-group}"
DB_SECURITYGROUP="crud-db-security-group"
MEMCACHE_SECURITYGROUP="crud-memcache-security-group"
DB_INSTANCE_ID="crud-mysql-db"
CACHE_NAME="crud-memcached"

echo "🧹 Starting cleanup of AWS resources..."

# Terminate EC2 instances
echo "🔍 Finding EC2 instances..."
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${INSTANCE_NAME}" "Name=instance-state-name,Values=running,stopped" \
  --query 'Reservations[*].Instances[*].InstanceId' --output text)

if [ ! -z "$INSTANCE_IDS" ]; then
  echo "🗑️ Terminating EC2 instances: ${INSTANCE_IDS}"
  aws ec2 terminate-instances --instance-ids $INSTANCE_IDS >/dev/null 2>&1
  echo "⏳ Waiting for instances to terminate..."
  aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS
  echo "✅ EC2 instances terminated"
else
  echo "ℹ️ No EC2 instances found"
fi

# Delete Memcached serverless cache
echo "🔍 Checking Memcached cache..."
CACHE_EXISTS=$(aws elasticache describe-serverless-caches --serverless-cache-name ${CACHE_NAME} --query 'ServerlessCaches[0].ServerlessCacheName' --output text 2>/dev/null)

if [ ! -z "$CACHE_EXISTS" ] && [ "$CACHE_EXISTS" != "None" ]; then
  echo "🗑️ Deleting Memcached cache: ${CACHE_NAME}"
  aws elasticache delete-serverless-cache --serverless-cache-name ${CACHE_NAME} >/dev/null 2>&1
  echo "⏳ Waiting for cache to delete..."
  sleep 30
  echo "✅ Memcached cache deleted"
else
  echo "ℹ️ No Memcached cache found"
fi

# Delete RDS instance
echo "🔍 Checking RDS instance..."
RDS_EXISTS=$(aws rds describe-db-instances --db-instance-identifier ${DB_INSTANCE_ID} --query 'DBInstances[0].DBInstanceIdentifier' --output text 2>/dev/null)

if [ ! -z "$RDS_EXISTS" ] && [ "$RDS_EXISTS" != "None" ]; then
  echo "🗑️ Deleting RDS instance: ${DB_INSTANCE_ID}"
  aws rds delete-db-instance \
    --db-instance-identifier ${DB_INSTANCE_ID} \
    --skip-final-snapshot >/dev/null 2>&1
  echo "⏳ Waiting for RDS instance to delete (this may take 5-10 minutes)..."
  aws rds wait db-instance-deleted --db-instance-identifier ${DB_INSTANCE_ID}
  echo "✅ RDS instance deleted"
else
  echo "ℹ️ No RDS instance found"
fi

# Delete cache subnet group
echo "🗑️ Deleting cache subnet group..."
aws elasticache delete-cache-subnet-group --cache-subnet-group-name crud-cache-subnet-group >/dev/null 2>&1
echo "✅ Cache subnet group deleted"

# Delete DB subnet group
echo "🗑️ Deleting DB subnet group..."
aws rds delete-db-subnet-group --db-subnet-group-name crud-db-subnet-group >/dev/null 2>&1
echo "✅ DB subnet group deleted"

# Delete security groups
echo "🗑️ Deleting security groups..."

# Delete Memcache security group
MEMCACHE_SG_ID=$(aws ec2 describe-security-groups --group-names ${MEMCACHE_SECURITYGROUP} --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
if [ ! -z "$MEMCACHE_SG_ID" ] && [ "$MEMCACHE_SG_ID" != "None" ]; then
  aws ec2 delete-security-group --group-id ${MEMCACHE_SG_ID} >/dev/null 2>&1
  echo "✅ Deleted Memcache security group"
fi

# Delete DB security group
DB_SG_ID=$(aws ec2 describe-security-groups --group-names ${DB_SECURITYGROUP} --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
if [ ! -z "$DB_SG_ID" ] && [ "$DB_SG_ID" != "None" ]; then
  aws ec2 delete-security-group --group-id ${DB_SG_ID} >/dev/null 2>&1
  echo "✅ Deleted DB security group"
fi

# Delete EC2 security group
EC2_SG_ID=$(aws ec2 describe-security-groups --group-names ${SECURITYGROUP} --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
if [ ! -z "$EC2_SG_ID" ] && [ "$EC2_SG_ID" != "None" ]; then
  aws ec2 delete-security-group --group-id ${EC2_SG_ID} >/dev/null 2>&1
  echo "✅ Deleted EC2 security group"
fi

echo "
🎉 Cleanup complete!

All resources have been removed:
- EC2 instances
- Memcached serverless cache
- RDS MySQL instance
- Cache subnet group
- DB subnet group
- Security groups
"
