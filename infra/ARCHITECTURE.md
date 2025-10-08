# Infrastructure Architecture

## Overview

Professional, production-grade infrastructure for GPU-based LLM fine-tuning on AWS.

## Design Principles

1. **Cost-Optimized:** Spot instances, auto-termination, lifecycle policies
2. **Secure:** OIDC authentication, no static credentials, SSM access, encryption at rest
3. **Easy to Use:** One command to spin up/down, automatic training execution
4. **Observable:** CloudWatch logs, SNS alerts, budget monitoring
5. **Professional:** Follows AWS best practices, modular Terraform design

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              CI/CD Pipeline                              │
│                                                                           │
│  ┌──────────────┐         ┌─────────────────┐         ┌──────────────┐ │
│  │   GitHub     │────────▶│  GitHub Actions │────────▶│     ECR      │ │
│  │  Repository  │         │   (OIDC Auth)   │         │  Repository  │ │
│  └──────────────┘         └─────────────────┘         └──────────────┘ │
│                                                              │            │
└──────────────────────────────────────────────────────────────┼───────────┘
                                                               │
                                                               │ Docker Pull
                                                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          Training Environment                            │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                         VPC (10.1.0.0/16)                        │   │
│  │                                                                   │   │
│  │  ┌──────────────────────────────────────────────────────────┐   │   │
│  │  │              Public Subnet (10.1.1.0/24)                 │   │   │
│  │  │                                                            │   │   │
│  │  │   ┌────────────────────────────────────────────────┐     │   │   │
│  │  │   │         GPU Training Instance                  │     │   │   │
│  │  │   │  ┌──────────────────────────────────────────┐  │     │   │   │
│  │  │   │  │   Deep Learning AMI (Ubuntu 22.04)       │  │     │   │   │
│  │  │   │  │   - NVIDIA Drivers                       │  │     │   │   │
│  │  │   │  │   - CUDA 12.4                            │  │     │   │   │
│  │  │   │  │   - Docker + nvidia-docker               │  │     │   │   │
│  │  │   │  └──────────────────────────────────────────┘  │     │   │   │
│  │  │   │  ┌──────────────────────────────────────────┐  │     │   │   │
│  │  │   │  │   Training Container (PyTorch 2.5)       │  │     │   │   │
│  │  │   │  │   - Transformers, PEFT, TRL             │  │     │   │   │
│  │  │   │  │   - Your training code                   │  │     │   │   │
│  │  │   │  │   - LoRA fine-tuning                     │  │     │   │   │
│  │  │   │  └──────────────────────────────────────────┘  │     │   │   │
│  │  │   │                                                  │     │   │   │
│  │  │   │   Instance Type: g5.xlarge / p3.2xlarge        │     │   │   │
│  │  │   │   GPU: NVIDIA A10G / V100                      │     │   │   │
│  │  │   │   Spot: ~$0.30/hr (70% savings)               │     │   │   │
│  │  │   └────────────────────────────────────────────────┘     │   │   │
│  │  │                          │                                │   │   │
│  │  │                          │ Access via                    │   │   │
│  │  │                          │ AWS SSM                       │   │   │
│  │  │                          ▼                                │   │   │
│  │  │                   ┌─────────────┐                        │   │   │
│  │  │                   │ Security    │                         │   │   │
│  │  │                   │ Group       │                         │   │   │
│  │  │                   │ (Egress     │                         │   │   │
│  │  │                   │  Only)      │                         │   │   │
│  │  │                   └─────────────┘                        │   │   │
│  │  └──────────────────────────────────────────────────────────┘   │   │
│  │                          │                                       │   │
│  │                          │ Internet                             │   │
│  │                          │ Gateway                              │   │
│  │                          ▼                                       │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
                         │                            │
                         │                            │
         ┌───────────────┼────────────────┬──────────┼──────────────┐
         │               │                │          │              │
         ▼               ▼                ▼          ▼              ▼
┌────────────────┐ ┌──────────┐ ┌────────────┐ ┌──────────┐ ┌──────────────┐
│  S3: Training  │ │S3: Model │ │ CloudWatch │ │   SNS    │ │EventBridge + │
│      Data      │ │ Outputs  │ │    Logs    │ │  Alerts  │ │   Lambda     │
│                │ │          │ │            │ │          │ │ (Auto-term)  │
└────────────────┘ └──────────┘ └────────────┘ └──────────┘ └──────────────┘
```

## Component Breakdown

### 1. CI/CD Pipeline (GitHub Actions)

**Purpose:** Build and deploy training Docker images

**Components:**
- GitHub Actions workflow (`.github/workflows/build-push-ecr.yml`)
- OIDC provider for secure AWS authentication
- IAM role with ECR push permissions

**Security:**
- No static AWS credentials
- OIDC provides temporary credentials (1 hour expiry)
- Restricted to specific repository and branch

**Flow:**
1. Code pushed to `main` branch
2. GitHub Actions requests AWS credentials via OIDC
3. AWS STS validates and issues temporary credentials
4. Docker image built with PyTorch + CUDA + training code
5. Image pushed to ECR with git SHA and `latest` tags

### 2. Container Registry (ECR)

**Purpose:** Store versioned Docker training images

**Features:**
- Image scanning on push (security)
- Lifecycle policies (keep last 10 tagged, 3 untagged)
- Encryption at rest (AES256)
- Image provenance labels (git SHA, timestamp)

**Naming:** `<account-id>.dkr.ecr.<region>.amazonaws.com/llm-tuning-lab-training:<tag>`

### 3. Storage Layer (S3)

**Two buckets:**

#### Training Data Bucket
- **Purpose:** Input data for training (JSONL session logs)
- **Lifecycle:** Archive to Glacier after 90 days
- **Versioning:** Enabled (rollback capability)
- **Access:** Read-only from EC2 instance

#### Outputs Bucket
- **Purpose:** Model checkpoints, training outputs
- **Structure:** `runs/<timestamp>/checkpoints/`, `runs/<timestamp>/output/`
- **Lifecycle:** Intelligent Tiering after 30 days, Glacier after 180 days
- **Versioning:** Enabled
- **Markers:** `SUCCESS` or `FAILURE` files for each run

**Security:**
- Block all public access
- Encryption at rest (AES256)
- IAM-based access control

### 4. Training Compute (EC2)

**Instance Configuration:**
- **AMI:** Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 22.04)
- **Pre-installed:** NVIDIA drivers, CUDA 12.4, Docker, nvidia-docker2
- **Instance Types:**
  - `g5.xlarge`: A10G 24GB, 4 vCPU, 16GB RAM (~$0.30/hr spot)
  - `g5.2xlarge`: A10G 24GB, 8 vCPU, 32GB RAM (~$0.60/hr spot)
  - `p3.2xlarge`: V100 16GB, 8 vCPU, 61GB RAM (~$0.90/hr spot)
- **Storage:** 200GB gp3 EBS (encrypted)
- **Networking:** Public subnet, public IP, SSM access
- **Market:** Spot instances (70% savings) with one-time request

**User Data Script Flow:**
1. Update system, install dependencies
2. Configure nvidia-docker2
3. Login to ECR
4. Pull training image
5. Sync training data from S3
6. Run training in tmux session
7. Monitor training completion
8. Sync outputs to S3
9. Self-terminate (if `auto_shutdown=true`)

**IAM Permissions:**
- Read from training S3 bucket
- Write to outputs S3 bucket
- Pull from ECR
- Write to CloudWatch Logs
- Terminate self (for auto-shutdown)

**Security:**
- Security group: Egress-only (no inbound except optional SSH)
- SSM access (no SSH keys required)
- IMDSv2 enforced (metadata security)
- Encrypted EBS volume

### 5. Networking (VPC)

**Optional Dedicated VPC:**
- **CIDR:** 10.1.0.0/16
- **Public Subnet:** 10.1.1.0/24
- **Internet Gateway:** For ECR/S3/SSM access
- **NAT Gateway:** Not needed (public subnet with IGW)

**Alternative:** Use existing VPC
- Set `create_vpc = false`
- Provide existing `vpc_id` and `subnet_id`

### 6. Monitoring & Safety

**CloudWatch Logs:**
- `/var/log/training-setup.log` → Training setup process
- `/var/log/training.log` → Training execution logs
- Docker container logs → Captured by ECS log driver

**CloudWatch Alarms:**
- Max runtime exceeded
- Triggers SNS notification

**EventBridge + Lambda:**
- Periodic check (every hour)
- Compares instance runtime vs. `max_runtime_hours`
- Auto-terminates if exceeded
- Lambda function written in Python 3.12

**AWS Budgets:**
- Monthly budget alert
- Notifications at 80% and 100% of threshold
- Filtered by `Project=llm-tuning-lab` tag

**SNS Alerts:**
- Email notifications for:
  - Max runtime exceeded
  - Budget threshold reached
  - Manual subscription confirmation required

### 7. Access & Authentication

**Instance Access:**
- **Primary:** AWS Systems Manager (SSM) Session Manager
  - No SSH keys required
  - No inbound security group rules
  - Audited access logs
- **Optional:** SSH with key pair (not recommended)

**Service Authentication:**
- **GitHub Actions → AWS:** OIDC (temporary credentials)
- **EC2 → S3/ECR:** IAM instance profile
- **No static credentials stored anywhere**

## Deployment Patterns

### Development Pattern

```bash
# 1. Deploy infrastructure (one-time)
terraform apply

# 2. Upload training data
aws s3 sync data/ s3://$TRAINING_BUCKET/data/

# 3. Spin up instance
terraform apply -var="create_instance=true"

# 4. Training auto-starts, auto-terminates

# 5. Download results
aws s3 sync s3://$OUTPUTS_BUCKET/runs/latest/ ./outputs/
```

### Production Pattern

```bash
# 1. Use on-demand for reliability
terraform apply -var="create_instance=true" -var="use_spot=false"

# 2. Increase max runtime
terraform apply -var="max_runtime_hours=24"

# 3. Disable auto-shutdown for manual review
terraform apply -var="auto_shutdown=false"

# 4. Monitor closely
aws ssm start-session --target $INSTANCE_ID

# 5. Manual cleanup after validation
terraform destroy
```

## Cost Breakdown

### Compute (Primary Cost)

| Resource | Cost | When Charged |
|----------|------|--------------|
| g5.xlarge spot | ~$0.30/hr | While running |
| g5.xlarge on-demand | ~$1.00/hr | While running |
| EBS gp3 200GB | ~$16/month | Always |

**Typical training:** 2-6 hours = $0.60-$6.00

### Storage (Minimal)

| Resource | Cost | Typical |
|----------|------|---------|
| S3 Standard | $0.023/GB/mo | $2-5/mo |
| ECR | $0.10/GB/mo | $1-3/mo |

### Data Transfer

| Transfer | Cost |
|----------|------|
| S3 → EC2 (same region) | Free |
| ECR → EC2 (same region) | Free |
| Results download | $0.09/GB (first 10TB/mo) |

**Total monthly cost (idle):** ~$20-30 (storage + EBS)
**Total per training run:** ~$1-10 depending on instance type and duration

## Scaling Considerations

### Horizontal Scaling (Future)

Not currently implemented, but possible:
- ECS cluster with multiple GPU container instances
- Job queue (AWS Batch or SQS)
- Distributed training across multiple GPUs/nodes

### Vertical Scaling (Current)

Easily change instance types:
```hcl
instance_type = "p3.8xlarge"  # 4x V100 GPUs
```

### Multi-Region

Deploy infrastructure in multiple regions:
```bash
cp -r envs/training envs/training-eu
# Edit region in training-eu/training.tfvars
```

## Disaster Recovery

### Data Protection

- **S3 versioning:** Enabled on both buckets
- **Cross-region replication:** Not configured (can be added)
- **Backup strategy:** S3 lifecycle policies archive to Glacier

### Instance Failure

- **Spot interruption:** Training checkpoints every N steps, can resume
- **Hardware failure:** Terraform `apply` creates new instance
- **Data loss:** Training data and outputs in S3 (durable)

### State Management

- **Terraform state:** Local by default
- **Recommended:** Store in S3 with state locking (DynamoDB)

```hcl
terraform {
  backend "s3" {
    bucket = "your-terraform-state"
    key    = "llm-tuning-lab/training/terraform.tfstate"
    region = "us-west-2"
  }
}
```

## Security Architecture

### Defense in Depth

1. **Network Layer:** VPC with minimal ingress
2. **Instance Layer:** IMDSv2, encrypted volumes, SSM-only access
3. **Application Layer:** Container isolation, read-only data mounts
4. **Data Layer:** Encrypted S3/EBS, IAM-based access
5. **Identity Layer:** OIDC for CI/CD, instance profiles for EC2

### Compliance Considerations

- **GDPR:** Data encryption, access logging, data lifecycle policies
- **SOC 2:** Audit logs (CloudWatch, SSM), access controls, encryption
- **PCI DSS:** Not applicable (no payment data)

### Security Best Practices Implemented

✅ Encryption at rest (S3, EBS)
✅ Encryption in transit (HTTPS for S3/ECR)
✅ No static credentials
✅ Least privilege IAM
✅ Network isolation
✅ Audit logging
✅ Automated patching (AMI updates)
✅ Secret management (no hardcoded values)

## Operational Excellence

### Observability

- **Logs:** CloudWatch Logs
- **Metrics:** CloudWatch metrics (GPU utilization via nvidia-smi)
- **Traces:** Not implemented (could add AWS X-Ray)
- **Dashboards:** Not implemented (could add CloudWatch Dashboards)

### Automation

- **CI/CD:** GitHub Actions
- **Infrastructure:** Terraform
- **Training execution:** User-data script
- **Cleanup:** Auto-termination

### Cost Optimization

- **Spot instances:** 70% savings
- **Auto-termination:** No idle time
- **S3 lifecycle:** Automatic archival
- **ECR lifecycle:** Image cleanup
- **Budget alerts:** Proactive monitoring

## Future Enhancements

Potential improvements:

1. **SageMaker Training Jobs** - Fully managed alternative
2. **Step Functions** - Orchestrate multi-step training pipelines
3. **Distributed Training** - Multi-GPU/multi-node with PyTorch DDP
4. **Experiment Tracking** - MLflow or Weights & Biases integration
5. **Model Registry** - Versioned model artifacts with metadata
6. **A/B Testing** - SageMaker endpoints for model comparison
7. **Continuous Training** - Automatic retraining on new data
8. **Data Versioning** - DVC or AWS DataSync
9. **GPU Monitoring** - Custom CloudWatch metrics for GPU utilization
10. **Cost Dashboards** - Real-time cost tracking and forecasting

## References

- [AWS Deep Learning AMIs](https://docs.aws.amazon.com/dlami/latest/devguide/what-is-dlami.html)
- [EC2 Spot Instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-spot-instances.html)
- [GitHub OIDC on AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [AWS Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [PyTorch Distributed Training](https://pytorch.org/tutorials/intermediate/ddp_tutorial.html)


