# Architecture

## Overview

GPU training infrastructure on AWS designed for cost optimization and ease of use. Spot instances, auto-shutdown, and minimal security surface.

## Components

### CI/CD

GitHub Actions builds Docker images and pushes to ECR using OIDC (no static AWS keys). On push to main:
1. GH requests temporary AWS creds via OIDC
2. Builds PyTorch + CUDA + training code image
3. Pushes to ECR with git SHA tag

### Storage

**S3 Training Data Bucket**
- Inputs for training (JSONL session logs)
- Read-only from EC2
- Lifecycle: archive to Glacier after 90 days

**S3 Outputs Bucket**
- Model checkpoints and logs
- Structure: `runs/<timestamp>/checkpoints/`
- Lifecycle: Intelligent Tiering → Glacier
- SUCCESS/FAILURE markers for each run

**ECR**
- Training Docker images
- Lifecycle: keep last 10 tagged, 3 untagged
- Image scanning on push

### Compute

**EC2 Instances**
- Deep Learning AMI (Ubuntu 22.04, CUDA 12.4, nvidia-docker)
- g5.xlarge: A10G 24GB, ~$0.30/hr spot
- p3.2xlarge: V100 16GB, ~$0.90/hr spot
- 200GB gp3 encrypted storage

**User Data Flow**
1. Install dependencies, configure nvidia-docker
2. Login to ECR, pull training image
3. Sync training data from S3
4. Run training in tmux (survives SSH disconnects)
5. Sync outputs to S3
6. Self-terminate if `auto_shutdown=true`

**IAM Permissions**
- S3 read (training bucket)
- S3 write (outputs bucket)
- ECR pull
- CloudWatch Logs write
- Self-termination (ec2:TerminateInstances with tag condition)

### Networking

Optional dedicated VPC or use existing:
- Public subnet with Internet Gateway (for ECR/S3 access)
- Security group: egress-only
- No SSH, use SSM Session Manager
- IMDSv2 enforced

### Safety

**Auto-termination**
- User data script self-terminates when training completes
- EventBridge + Lambda checks runtime every hour
- CloudWatch alarm for max runtime

**Cost Controls**
- Spot instances (70% savings)
- Auto-shutdown prevents idle billing
- S3 lifecycle policies
- Budget alerts via SNS

### Access

**SSM Session Manager**
- No SSH keys or open ports
- Audited access logs
- Connect: `aws ssm start-session --target <instance-id>`

**OIDC for CI/CD**
- Temporary 1-hour credentials
- Scoped to specific repo + branch
- No credentials in GitHub

## Flow

```
Developer
  │
  ├─> git push
  │     │
  │     └─> GitHub Actions (OIDC) ──> ECR
  │
  ├─> terraform apply -var="create_instance=true"
  │     │
  │     └─> EC2 Instance (spot)
  │           ├─> pulls image from ECR
  │           ├─> downloads data from S3
  │           ├─> trains model
  │           ├─> uploads outputs to S3
  │           └─> terminates self
  │
  └─> aws s3 sync s3://<outputs>/ ./local/
```

## Security

**Defense Layers**
- Network: VPC with minimal ingress
- Instance: SSM-only access, IMDSv2, encrypted volumes
- Application: Container isolation
- Data: Encrypted S3/EBS, IAM-based access
- Identity: OIDC + instance profiles

**No Static Credentials**
- GitHub Actions: OIDC temporary creds
- EC2: Instance profile
- Secrets (HF token): AWS Secrets Manager

## Costs

**Compute** (primary cost)
- g5.xlarge spot: ~$0.30/hr while running
- Typical training: 2-6 hours = $0.60-2.00

**Storage** (minimal)
- S3: ~$2-5/month
- ECR: ~$1-3/month
- EBS: ~$16/month (only while instance exists)

**Data Transfer**
- S3 → EC2 same region: free
- ECR → EC2 same region: free
- Downloads: $0.09/GB

Monthly idle cost (no training): ~$5-10 (S3 + ECR only)

## Limitations

- Single GPU per instance (no multi-GPU yet)
- Spot can be interrupted (checkpointing recommended)
- Manual instance lifecycle (start/stop via terraform)
- No distributed training support
- Logs in CloudWatch (no dashboards by default)

## Future Improvements

- SageMaker Training Jobs (fully managed alternative)
- Multi-GPU with PyTorch DDP
- Experiment tracking (MLflow/W&B)
- Automated retraining pipelines
- Custom CloudWatch dashboards
- Cost forecasting
