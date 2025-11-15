# Deployment

## Setup (one time)

```bash
cd infra/envs/training
cp training.tfvars.example training.tfvars
vim training.tfvars  # edit as needed

terraform init
terraform apply -var-file=training.tfvars  # creates S3, ECR, no instance yet
```

Add the GitHub secret for OIDC:

```bash
terraform output github_actions_role_arn
# Add this to GitHub: Settings → Secrets → AWS_GHA_ROLE_ARN
```

Push to build the Docker image (or manually trigger GitHub Actions):

```bash
git push origin main  # builds and pushes to ECR
```

Upload your training data:

```bash
TRAINING_BUCKET=$(terraform output -raw training_bucket)
aws s3 sync data/ s3://$TRAINING_BUCKET/data/
```

## Running Training

Start an instance:

```bash
terraform apply -var="create_instance=true" -auto-approve
```

Costs ~$0.30/hr for g5.xlarge spot. Instance auto-starts training and terminates when done (if `auto_shutdown=true`).

Monitor it:

```bash
INSTANCE_ID=$(terraform output -raw instance_id)
aws ssm start-session --target $INSTANCE_ID

# inside:
tmux attach -t training
tail -f /var/log/training.log
nvidia-smi
```

Get results:

```bash
OUTPUTS_BUCKET=$(terraform output -raw outputs_bucket)
aws s3 ls s3://$OUTPUTS_BUCKET/runs/
aws s3 sync s3://$OUTPUTS_BUCKET/runs/20241005-143000/ ./outputs/
```

Kill the instance:

```bash
terraform destroy -auto-approve
```

## Quick Tweaks

Change instance type:

```bash
# edit training.tfvars: instance_type = "g5.2xlarge"
terraform apply -var="create_instance=true"
```

Use on-demand instead of spot:

```bash
terraform apply -var="create_instance=true" -var="use_spot=false"
```

Update training code:

```bash
git commit -am "update training"
git push  # wait for Actions to rebuild image
terraform apply -var="create_instance=true"
```

Emergency kill:

```bash
aws ec2 terminate-instances --instance-ids $(terraform output -raw instance_id)
```

## Troubleshooting

Can't push to ECR → check `AWS_GHA_ROLE_ARN` secret matches terraform output

Instance won't start → spot might be unavailable, try on-demand or different AZ

Training fails → `aws ssm start-session` and check `/var/log/training-setup.log`

No results in S3 → check `/var/log/training.log` for errors

