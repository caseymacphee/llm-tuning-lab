# Deployment Guide

Quick reference for deploying the LLM Tuning Lab training infrastructure.

## Initial Setup (One-Time)

### 1. Deploy Infrastructure

```bash
cd infra/envs/training

# Copy and configure
cp training.tfvars.example training.tfvars
vim training.tfvars  # Set your preferences

# Deploy (without instance)
terraform init
terraform apply -var-file=training.tfvars
```

### 2. Configure GitHub Secrets

After `terraform apply`, copy the output values:

```bash
# Get the IAM role ARN
terraform output github_actions_role_arn
```

Add to GitHub Repository:
1. Go to: **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret**
3. Add:
   - Name: `AWS_GHA_ROLE_ARN`
   - Value: `arn:aws:iam::ACCOUNT_ID:role/llm-tuning-lab-github-actions-role`

**That's the only secret needed!** ✅ No AWS access keys required.

### 3. Build and Push Docker Image

Push code to trigger the GitHub Actions workflow:

```bash
git add .
git commit -m "Setup infrastructure"
git push origin main
```

Or manually trigger:
- Go to: **Actions** → **Build and Push Training Image to ECR** → **Run workflow**

Wait ~5-10 minutes for the image to build and push.

### 4. Upload Training Data

```bash
# Get bucket name
cd infra/envs/training
TRAINING_BUCKET=$(terraform output -raw training_bucket)

# Upload your training data
aws s3 sync ../../data/ s3://$TRAINING_BUCKET/data/
```

## Running Training

### Start Training Instance

```bash
cd infra/envs/training

# Spin up GPU instance
terraform apply -var-file=training.tfvars -var="create_instance=true" -auto-approve
```

**Cost:** ~$0.30/hr (g5.xlarge spot) or ~$1.00/hr (on-demand)

The instance will:
1. Start up (~2-3 minutes)
2. Pull Docker image from ECR
3. Download training data from S3
4. Start training automatically
5. Upload results to S3
6. **Auto-terminate** when complete (if `auto_shutdown=true`)

### Monitor Training

```bash
# Get instance ID
INSTANCE_ID=$(terraform output -raw instance_id)

# Connect via SSM (no SSH key needed)
aws ssm start-session --target $INSTANCE_ID
```

Inside the instance:

```bash
# Attach to training session
tmux attach -t training

# Or view logs
tail -f /var/log/training.log

# Check GPU usage
nvidia-smi

# Exit SSM
exit
```

### Check Results

```bash
# Get outputs bucket
OUTPUTS_BUCKET=$(terraform output -raw outputs_bucket)

# List training runs
aws s3 ls s3://$OUTPUTS_BUCKET/runs/

# Download a specific run
aws s3 sync s3://$OUTPUTS_BUCKET/runs/20241005-143000/ ./outputs/
```

### Stop Training Instance

If auto-shutdown is disabled or you need to manually stop:

```bash
cd infra/envs/training
terraform destroy -var-file=training.tfvars -auto-approve
```

## Quick Commands

### Check Infrastructure Status

```bash
cd infra/envs/training
terraform output
```

### Update Training Code

```bash
# Make changes to lab/*.py
git commit -am "Update training script"
git push origin main

# Wait for GitHub Actions to build new image
# Then spin up instance with new code
terraform apply -var="create_instance=true"
```

### Change Instance Type

```bash
# Edit training.tfvars
instance_type = "g5.2xlarge"

# Apply changes
terraform apply -var-file=training.tfvars -var="create_instance=true"
```

### Use On-Demand Instead of Spot

```bash
terraform apply -var-file=training.tfvars \
  -var="create_instance=true" \
  -var="use_spot=false"
```

### Emergency Stop (Kill Instance Immediately)

```bash
INSTANCE_ID=$(cd infra/envs/training && terraform output -raw instance_id)
aws ec2 terminate-instances --instance-ids $INSTANCE_ID
```

## Cost Estimates

### Instance Costs (Spot Pricing)

| Training Time | g5.xlarge | g5.2xlarge | p3.2xlarge |
|--------------|-----------|------------|------------|
| 2 hours | $0.60 | $1.20 | $1.80 |
| 6 hours | $1.80 | $3.60 | $5.40 |
| 12 hours | $3.60 | $7.20 | $10.80 |

### Storage Costs (Minimal)

- **S3 Standard:** ~$0.023/GB/month
- **ECR:** $0.10/GB/month
- **Typical:** $1-5/month for data and images

**Total:** Most cost is GPU compute time, storage is negligible.

## Troubleshooting

### Image Build Fails

Check GitHub Actions logs:
1. Go to: **Actions** → **Build and Push Training Image to ECR**
2. Click on the failed run
3. Check logs for errors

Common issues:
- Ensure `AWS_GHA_ROLE_ARN` secret is set correctly
- Check Terraform output matches the secret value

### Instance Won't Start

```bash
# Check Terraform state
cd infra/envs/training
terraform show

# Check AWS console for spot availability
# Try different AZ or use on-demand:
terraform apply -var="use_spot=false"
```

### Training Fails

```bash
# Connect to instance
aws ssm start-session --target $(terraform output -raw instance_id)

# Check setup logs
sudo cat /var/log/training-setup.log

# Check training logs
sudo cat /var/log/training.log

# Check Docker logs
sudo docker ps -a
sudo docker logs <container-id>
```

### Can't Find Training Outputs

```bash
# List all runs
OUTPUTS_BUCKET=$(cd infra/envs/training && terraform output -raw outputs_bucket)
aws s3 ls s3://$OUTPUTS_BUCKET/runs/ --recursive

# Check for SUCCESS or FAILURE markers
aws s3 ls s3://$OUTPUTS_BUCKET/runs/ --recursive | grep -E 'SUCCESS|FAILURE'
```

## Security Notes

✅ **What we're using:**
- OIDC for GitHub Actions (no static AWS credentials in GitHub)
- SSM for instance access (no SSH keys or open ports)
- Encrypted S3 buckets and EBS volumes
- Minimal IAM permissions (scoped to specific resources)

❌ **What to avoid:**
- Never commit AWS credentials to the repository
- Never expose the instance with public security groups
- Don't use root user for AWS operations
- Don't keep instances running when not training

## Best Practices

1. **Always set `auto_shutdown=true`** for development training
2. **Use spot instances** unless production-critical
3. **Start small** - test with g5.xlarge before scaling up
4. **Monitor costs** - set up `alert_email` in tfvars
5. **Tag training runs** - use descriptive run IDs in S3
6. **Clean up old outputs** - S3 lifecycle rules help, but manual cleanup is faster

## Support

For issues:
1. Check logs (`/var/log/training.log`, `/var/log/training-setup.log`)
2. Review GitHub Actions logs
3. Check Terraform state
4. Verify AWS quotas (especially for GPU instances)

For infrastructure questions, see: `infra/README.md`

