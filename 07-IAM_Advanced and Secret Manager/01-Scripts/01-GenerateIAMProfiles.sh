#!/bin/bash

USER_NAME="${1}"
PROFILE="${2}"

PROFILE_FILE="$HOME/.aws/credentials"
BACKUP_FILE="$HOME/.aws/credentials-backup-$(date +%Y%m%d%H%M%S)"
SED_COMMAND="sed -i"

# Define input file
INPUT_FILE="./06-AccessKeys/${USER_NAME}-key.json"

# Check if file exists
if [[ ! -f "$INPUT_FILE" ]]; then
  echo "❌ Input file '$INPUT_FILE' not found. Please place it in the same directory."
  exit 1
fi

# AWS variable patterns to remove
VARS=("aws_access_key_id" "aws_secret_access_key")

# Backup the profile file
cp "$PROFILE_FILE" "$BACKUP_FILE"
echo "🛡️ Backup created: $BACKUP_FILE"

# Remove matching lines
#echo "🧹 Removed AWS-related environment variables from $PROFILE_FILE"
#for VAR in "${VARS[@]}"; do
#  ${SED_COMMAND} "/$VAR=/d" "$PROFILE_FILE"
#  echo $VAR
#done

# Clean up temp backup
#rm -f "$PROFILE_FILE"

# Check for jq
if ! command -v jq &> /dev/null; then
  echo "❌ 'jq' is required but not installed. Please install jq and try again."
  exit 1
fi

# Read values from file
AWS_ACCESS_KEY=$(jq -r '.AccessKey.AccessKeyId' "$INPUT_FILE")
AWS_SECRET_KEY=$(jq -r '.AccessKey.SecretAccessKey' "$INPUT_FILE")

if [[ -z "$AWS_ACCESS_KEY" || -z "$AWS_SECRET_KEY" ]]; then
  echo "❌ Failed to extract credentials. Please check the JSON input."
  exit 1
fi
# Write to ~/.profile
{
  echo "[${PROFILE}]"
  echo "aws_access_key_id=$AWS_ACCESS_KEY"
  echo "aws_secret_access_key=$AWS_SECRET_KEY"
  echo "region=us-east-1"
} >> "$PROFILE_FILE"

echo "✅ AWS credentials profile [${PROFILE}] created with environment variables saved to $PROFILE_FILE"

# Reload profile
#echo "🔄 Reloading profile..."
#source "$PROFILE_FILE"