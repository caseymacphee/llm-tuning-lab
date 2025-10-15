#!/bin/bash
echo "=== GPU Quota Request Status ==="
echo ""

echo "1. On-Demand G and VT Instances:"
aws service-quotas get-requested-service-quota-change \
  --request-id 8c9141ae7e924cd289e22115b9bbe022LuLrlpDM \
  --region us-west-2 \
  --query 'RequestedQuota.{Status:Status,Desired:DesiredValue,Created:Created}' \
  --output table

echo ""
echo "2. Spot G and VT Instances:"
aws service-quotas get-requested-service-quota-change \
  --request-id 4d86037ffb6a4bcb8558611a46885d603m9r26ZG \
  --region us-west-2 \
  --query 'RequestedQuota.{Status:Status,Desired:DesiredValue,Created:Created}' \
  --output table

echo ""
echo "Possible statuses: PENDING → CASE_OPENED → APPROVED"
echo "Usually takes 24-48 hours for ML training use cases"
