#!/bin/bash

INSTANCE_ID="i-09c1e31ac940d1d1a"
OUTPUT_BUCKET="llm-tuning-lab-outputs-training"

echo "========================================="
echo "Training Instance Monitor"
echo "========================================="
echo ""

# Check instance status
echo "1. Instance Status:"
aws ec2 describe-instances --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].{State:State.Name,Type:InstanceType,IP:PublicIpAddress,LaunchTime:LaunchTime}' \
  --output table

echo ""
echo "2. System Health:"
aws ec2 describe-instance-status --instance-ids $INSTANCE_ID \
  --query 'InstanceStatuses[0].{Instance:InstanceStatus.Status,System:SystemStatus.Status}' \
  --output table 2>/dev/null || echo "  Still booting..."

echo ""
echo "3. Recent S3 Output Activity:"
aws s3 ls s3://$OUTPUT_BUCKET/runs/ --recursive --human-readable | tail -10 || echo "  No outputs yet"

echo ""
echo "========================================="
echo "To connect and view logs:"
echo "  aws ssm start-session --target $INSTANCE_ID"
echo ""
echo "Once connected, run:"
echo "  tail -f /var/log/training-setup.log  # Setup logs"
echo "  tail -f /var/log/training.log        # Training logs"
echo "  tmux attach -t training              # Attach to training session"
echo "========================================="
