# Infrastructure

Terraform setup for running GPU training on AWS. Uses spot instances, auto-shutdown, and OIDC for GitHub Actions.

## Architecture

- **Compute**: GPU EC2 (g5.xlarge, p3.2xlarge) with spot support
- **Storage**: S3 for data + outputs, ECR for Docker images
- **Access**: SSM Session Manager (no SSH keys)
- **CI/CD**: GitHub Actions OIDC (no static credentials)
- **Safety**: Auto-termination, max runtime alarms, cost alerts

## Setup

```bash
cd envs/training
cp training.tfvars.example training.tfvars
vim training.tfvars

terraform init
terraform apply -var-file=training.tfvars
```

Set the GitHub secret:

```bash
terraform output github_actions_role_arn
# Add to GitHub: Settings → Secrets → AWS_GHA_ROLE_ARN
```

## Modules

- `training-storage`: S3 buckets with lifecycle policies
- `training-registry`: ECR + GitHub OIDC role
- `training-compute`: EC2 instances with auto-start training
- `training-safety`: CloudWatch alarms, auto-termination

## Configuration

Key vars in `training.tfvars`:

```hcl
instance_type = "g5.xlarge"  # A10G 24GB, ~$0.30/hr spot
use_spot = true              # 70% cost savings
auto_shutdown = true         # terminate when done
max_runtime_hours = 12       # safety cutoff
```

## Costs

| Instance | GPU | Spot $/hr | Typical Run |
|----------|-----|-----------|-------------|
| g5.xlarge | A10G 24GB | ~$0.30 | $0.60-2.00 |
| g5.2xlarge | A10G 24GB | ~$0.60 | $1.20-4.00 |
| p3.2xlarge | V100 16GB | ~$0.90 | $1.80-6.00 |

Storage (S3 + ECR) is ~$20-30/month.

## Workflow

```bash
# 1. Push code
git push origin main  # triggers ECR build

# 2. Upload data
aws s3 sync data/ s3://$(terraform output -raw training_bucket)/data/

# 3. Start training
terraform apply -var="create_instance=true"

# 4. Monitor
aws ssm start-session --target $(terraform output -raw instance_id)

# 5. Get results
aws s3 sync s3://$(terraform output -raw outputs_bucket)/runs/latest/ ./outputs/

# 6. Cleanup
terraform destroy
```

## Troubleshooting

GitHub Actions can't push to ECR:
- Check `AWS_GHA_ROLE_ARN` secret matches terraform output

Spot instance won't start:
- Try on-demand: `terraform apply -var="use_spot=false"`
- Or different AZ in tfvars

Training fails:
- SSM into instance: `aws ssm start-session --target <id>`
- Check logs: `/var/log/training-setup.log` and `/var/log/training.log`

OOM errors:
- Use larger instance or reduce batch size via env vars

## Security

- OIDC for GitHub Actions (no static credentials)
- SSM for access (no SSH, no open ports)
- Encrypted S3 + EBS
- Minimal IAM permissions
- IMDSv2 enforced

See `ARCHITECTURE.md` for detailed design.
