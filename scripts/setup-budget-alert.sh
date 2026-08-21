#!/usr/bin/env bash
set -euo pipefail
ACCOUNT_ID="${1:?Usage: setup-budget-alert.sh <ACCOUNT_ID> <ALERT_EMAIL>}"
EMAIL="${2:?Usage: setup-budget-alert.sh <ACCOUNT_ID> <ALERT_EMAIL>}"

aws budgets create-budget --account-id "$ACCOUNT_ID" \
  --budget "{
    \"BudgetName\": \"devops-eks-project-budget\",
    \"BudgetLimit\": {\"Amount\": \"5\", \"Unit\": \"USD\"},
    \"TimeUnit\": \"MONTHLY\",
    \"BudgetType\": \"COST\"
  }" \
  --notifications-with-subscribers "[{
    \"Notification\": {\"NotificationType\":\"ACTUAL\",\"ComparisonOperator\":\"GREATER_THAN\",\"Threshold\":80},
    \"Subscribers\": [{\"SubscriptionType\":\"EMAIL\",\"Address\":\"$EMAIL\"}]
  }]"

echo "Budget alert created — you'll get an email at 80% of \$5."
