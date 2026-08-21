#!/usr/bin/env bash
# Run ONCE, before the first `terraform init`, to create the S3 bucket +
# DynamoDB table that hold Terraform state. These two resources are outside
# Terraform's own management on purpose (a backend can't create itself).
set -euo pipefail

BUCKET_NAME="${1:-devops-eks-tfstate-$(date +%s)}"
REGION="${2:-us-east-1}"

echo "Creating state bucket: $BUCKET_NAME in $REGION"
aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION" \
  $( [ "$REGION" != "us-east-1" ] && echo "--create-bucket-configuration LocationConstraint=$REGION" )

aws s3api put-bucket-versioning --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

echo "Creating lock table: tf-locks"
aws dynamodb create-table \
  --table-name tf-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION"

echo ""
echo "Done. Put this bucket name into terraform/environments/dev/backend.tf, then run:"
echo "  terraform init"
