# LLM Tuning Lab - Infrastructure

Production-grade Terraform infrastructure for running GPU-based LLM fine-tuning on AWS.

## Architecture Overview

This infrastructure provides:
- **GPU EC2 instances** (g5.xlarge/p3.2xlarge) for training with spot instance support
- **S3 buckets** for training data and model outputs
- **ECR repository** for Docker training images
- **SSM access** for secure instance management (no SSH keys required)
- **Auto-termination** safety features to control costs
- **GitHub Actions OIDC** integration for secure CI/CD (no static AWS credentials)

## Quick Start

### 1. Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.7.0
- GitHub repository set up

### 2. Initial Infrastructure Setup

```bash
cd infra/envs/training

# Copy example config
cp training.tfvars.example training.tfvars

# Edit training.tfvars with your settings
vim training.tfvars

# Initialize Terraform
terraform init

# Create infrastructure (without instance)
terraform apply -var-file=training.tfvars
```

**Important:** Keep `create_instance = false` initially. This creates the S3 buckets and ECR repository but doesn't start any expensive GPU instances.

### 3. GitHub Actions Setup

After running `terraform apply`, you'll get outputs including `github_actions_role_arn`. Add this to your GitHub repository:

#### Required GitHub Secret:

Go to: `Settings > Secrets and variables > Actions > New repository secret`

```
AWS_GHA_ROLE_ARN = <output from terraform: github_actions_role_arn>
```

Example: `arn:aws:iam::123456789012:role/llm-tuning-lab-github-actions-role`

**That's it!** No AWS access keys needed. GitHub Actions will use OIDC to assume the role.

### 4. Push Training Image to ECR

```bash
# Trigger the GitHub Actions workflow
git add .
git commit -m "Initial setup"
git push origin main

# Or manually trigger:
# Go to Actions > Build and Push Training Image to ECR > Run workflow
```

This automatically builds and pushes your Docker image to ECR.

### 5. Upload Training Data to S3

```bash
# Get bucket name from Terraform output
TRAINING_BUCKET=$(terraform output -raw training_bucket)

# Upload your training data
aws s3 sync ../data/ s3://$TRAINING_BUCKET/data/
```

### 6. Spin Up Training Instance

```bash
# Start training instance
terraform apply -var-file=training.tfvars -var="create_instance=true"

# Wait for instance to start (2-3 minutes for Deep Learning AMI)
# Training begins automatically via user-data script
```

### 7. Monitor Training

```bash
# Get instance ID
INSTANCE_ID=$(terraform output -raw instance_id)

# Connect via Systems Manager (no SSH key needed)
aws ssm start-session --target $INSTANCE_ID

# Inside instance, attach to training session
tmux attach -t training

# Or view logs
tail -f /var/log/training.log
tail -f /var/log/training-setup.log
```

### 8. Cleanup (IMPORTANT!)

```bash
# Destroy training instance when done
terraform destroy -var-file=training.tfvars

# Confirm destruction
# This terminates the GPU instance and stops billing
```

**Note:** S3 buckets and ECR repository persist (minimal cost). Only destroy them if you're done with the project entirely.

## Cost Management

### Instance Costs (us-west-2)

| Instance Type | GPU | VRAM | Spot Price | On-Demand | Use Case |
|--------------|-----|------|------------|-----------|----------|
| g5.xlarge | A10G | 24GB | ~$0.30/hr | ~$1.00/hr | 7-8B models (recommended) |
| g5.2xlarge | A10G | 24GB | ~$0.60/hr | ~$2.00/hr | Faster CPU/memory |
| p3.2xlarge | V100 | 16GB | ~$0.90/hr | ~$3.00/hr | Mature ecosystem |
| p3.8xlarge | 4x V100 | 64GB | ~$3.60/hr | ~$12.00/hr | Multi-GPU, large models |

### Safety Features

This infrastructure includes automatic cost controls:

1. **Auto-shutdown:** Instance terminates when training completes (`auto_shutdown = true`)
2. **Max runtime alarm:** Terminates after X hours (default: 12)
3. **Cost alerts:** Email notification when threshold exceeded
4. **Spot instances:** 70% cost savings with automatic checkpointing

### Typical Training Costs

- **8B model, 2 epochs, g5.xlarge spot:** $0.60 - $2.00 (2-6 hours)
- **8B model, 2 epochs, p3.2xlarge spot:** $1.80 - $5.40 (2-6 hours)

## Configuration

### Key Variables (`training.tfvars`)

```hcl
# Instance Configuration
create_instance = false      # Set to true to spin up
instance_type   = "g5.xlarge"
use_spot        = true       # 70% cost savings
volume_size     = 200        # GB for models + checkpoints

# Safety Features
max_runtime_hours    = 12    # Auto-terminate after
cost_alert_threshold = 50    # Alert if costs exceed $50
alert_email          = "you@example.com"

# Training
auto_shutdown = true         # Terminate when done
```

### Environment Variables (on instance)

The training script uses environment variables with `LLM_` prefix:

```bash
# Example: Configure via environment
export LLM_MODEL__BASE_MODEL="meta-llama/Meta-Llama-3-8B-Instruct"
export LLM_TRAINING__NUM_TRAIN_EPOCHS=3
export LLM_TRAINING__LEARNING_RATE=2e-4
export LLM_LORA__R=16

# Or modify user-data.sh template to inject variables
```

## Workflows

### Development Workflow

```bash
# 1. Make changes to training code locally
git commit -am "Improved training parameters"

# 2. Push to trigger ECR build
git push origin main

# 3. Wait for GitHub Actions to complete (~5-10 min)

# 4. Spin up training instance
terraform apply -var="create_instance=true" -auto-approve

# 5. Monitor via SSM
aws ssm start-session --target $(terraform output -raw instance_id)

# 6. Training auto-terminates when complete
# Or manually destroy:
terraform destroy -auto-approve
```

### Production Workflow

For production runs with important experiments:

```bash
# Use on-demand instead of spot (no interruption risk)
terraform apply -var="create_instance=true" -var="use_spot=false"

# Increase max runtime for longer training
terraform apply -var="max_runtime_hours=24"

# Disable auto-shutdown to review results
terraform apply -var="auto_shutdown=false"
```

## Troubleshooting

### GitHub Actions Can't Push to ECR

**Error:** `Unable to locate credentials`

**Fix:** Ensure `AWS_GHA_ROLE_ARN` secret is set correctly:
```bash
# Get the role ARN from Terraform
terraform output github_actions_role_arn

# Add to GitHub: Settings > Secrets > AWS_GHA_ROLE_ARN
```

### Instance Fails to Start

**Error:** Spot instance not available

**Fix:** Switch to on-demand or try different AZ:
```hcl
use_spot = false
# Or
availability_zone = "us-west-2b"
```

### Training Container Won't Start

**Error:** `docker: Error response from daemon: could not select device driver`

**Fix:** Deep Learning AMI should have nvidia-docker pre-installed. Check logs:
```bash
aws ssm start-session --target <instance-id>
cat /var/log/training-setup.log
sudo docker run --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi
```

### Out of Memory (OOM)

**Error:** CUDA out of memory

**Fix:** Reduce batch size or use larger instance:
```bash
# Reduce batch size
export LLM_TRAINING__PER_DEVICE_TRAIN_BATCH_SIZE=1
export LLM_TRAINING__GRADIENT_ACCUMULATION_STEPS=16

# Or upgrade instance
terraform apply -var="instance_type=g5.2xlarge"
```

### Training Results Not in S3

Check the outputs bucket:
```bash
OUTPUTS_BUCKET=$(terraform output -raw outputs_bucket)
aws s3 ls s3://$OUTPUTS_BUCKET/runs/ --recursive
```

Instance logs:
```bash
aws ssm start-session --target $(terraform output -raw instance_id)
tail -f /var/log/training.log
```

## Advanced Topics

### Custom Training Parameters

Edit the user-data script template to inject environment variables:

```bash
# infra/modules/training-compute/user-data.sh
# Add before docker run:
export LLM_TRAINING__NUM_TRAIN_EPOCHS=5
export LLM_TRAINING__LEARNING_RATE=1e-4
```

### Multi-Region Setup

Deploy in different regions for lower latency or spot availability:

```bash
cp -r envs/training envs/training-eu

# Edit envs/training-eu/training.tfvars
region = "eu-west-1"
availability_zone = "eu-west-1a"
```

### State Management

For production, use remote state:

```hcl
# envs/training/main.tf
terraform {
  backend "s3" {
    bucket = "your-terraform-state-bucket"
    key    = "llm-tuning-lab/training/terraform.tfstate"
    region = "us-west-2"
  }
}
```

## Module Reference

### training-storage
- Creates S3 buckets for data and outputs
- Lifecycle policies for cost optimization
- Encryption and versioning enabled

### training-registry
- ECR repository for Docker images
- GitHub OIDC provider and IAM role
- Image lifecycle policies

### training-compute
- GPU EC2 instance (spot or on-demand)
- Optional dedicated VPC
- IAM roles for S3/ECR access
- SSM for secure access
- Automated training via user-data

### training-safety
- CloudWatch alarms for max runtime
- Lambda function for auto-termination
- SNS alerts for cost thresholds
- AWS Budgets integration

## Security Best Practices

1. **No static AWS credentials:** Uses OIDC for GitHub Actions
2. **SSM access:** No SSH keys or exposed ports required
3. **Private subnets:** Instances can use private subnets (set `create_vpc=false`, provide private subnet)
4. **Encrypted storage:** S3 and EBS volumes use encryption
5. **IMDSv2:** Enforced on EC2 instances
6. **Minimal IAM permissions:** Scoped to specific resources

## Contributing

When modifying infrastructure:

1. Test in isolated environment
2. Run `terraform fmt` before committing
3. Update this README if changing behavior
4. Tag releases for production deployments

## License

See main repository LICENSE file.


