#!/usr/bin/env bash
# Run this at the end of every work session. This is the single biggest
# cost lever in the whole project — an idle EKS cluster + NAT gateway will
# quietly burn ~$3-4/day even doing nothing.
set -euo pipefail

echo "Deleting Kubernetes workloads..."
kubectl delete -f k8s/ --ignore-not-found=true || true

echo "Uninstalling monitoring stack..."
helm uninstall monitoring -n monitoring 2>/dev/null || true

echo "Destroying Terraform-managed infrastructure..."
cd terraform/environments/dev
terraform destroy -auto-approve

echo ""
echo "Verifying nothing billable is left running:"
aws eks list-clusters
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType]' --output table
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName' --output table
