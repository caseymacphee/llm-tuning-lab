#!/bin/bash
set -e
set -o pipefail

# Logging setup
LOGFILE="/var/log/training-setup.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "========================================"
echo "Training Instance Setup Started: $(date)"
echo "========================================"

# Environment variables from template
export AWS_DEFAULT_REGION="${region}"
export ECR_REPOSITORY_URL="${ecr_repository_url}"
export DOCKER_IMAGE_TAG="${docker_image_tag}"
export TRAINING_BUCKET="${training_bucket}"
export OUTPUTS_BUCKET="${outputs_bucket}"
export TRAINING_COMMAND="${training_command}"
export AUTO_SHUTDOWN="${auto_shutdown}"
export DEBIAN_FRONTEND=noninteractive

# Wait for unattended-upgrades to finish (race condition on AMI first boot)
echo "Waiting for any system package manager locks to be released..."
max_wait=300  # 5 minutes
waited=0
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 ; do
    echo "Waiting for dpkg lock to be released... ($waited/$max_wait seconds)"
    sleep 10
    waited=$((waited + 10))
    if [ $waited -ge $max_wait ]; then
        echo "WARNING: Timed out waiting for package lock. Proceeding anyway..."
        break
    fi
done
echo "Package manager is ready"

# Update system
echo "Updating system packages..."
apt-get update -y
apt-get upgrade -y

# Install required packages (Docker already on Deep Learning AMI)
echo "Installing required packages..."
apt-get install -y \
    jq \
    unzip \
    htop \
    tmux || echo "Warning: Some packages already installed"

# Ensure Docker service is running
echo "Ensuring Docker service is running..."
systemctl enable docker || true
systemctl start docker || true

# Install nvidia-docker2 for GPU support
echo "Installing nvidia-docker2..."
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
    tee /etc/apt/sources.list.d/nvidia-docker.list
apt-get update
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" nvidia-docker2
systemctl restart docker

# Verify GPU is available
echo "Verifying GPU availability..."
nvidia-smi

# Login to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region $AWS_DEFAULT_REGION | \
    docker login --username AWS --password-stdin $ECR_REPOSITORY_URL

# Pull training image
echo "Pulling training image: $ECR_REPOSITORY_URL:$DOCKER_IMAGE_TAG"
docker pull $ECR_REPOSITORY_URL:$DOCKER_IMAGE_TAG

# Create workspace directories
echo "Creating workspace directories..."
mkdir -p /workspace/data
mkdir -p /workspace/output
mkdir -p /workspace/checkpoints

# Sync training data from S3
echo "Syncing training data from S3..."
if aws s3 ls s3://$TRAINING_BUCKET/ > /dev/null 2>&1; then
    aws s3 sync s3://$TRAINING_BUCKET/data/ /workspace/data/ --quiet
    echo "Training data synced successfully"
else
    echo "WARNING: Training bucket is empty or inaccessible"
fi

# Create training script wrapper
cat > /workspace/run_training.sh << EOF
#!/bin/bash
set -e

# Start timestamp
START_TIME=\$(date +%s)
RUN_ID=\$(date +%Y%m%d-%H%M%S)

echo "========================================"
echo "Training Run Started: \$(date)"
echo "Run ID: \$RUN_ID"
echo "========================================"

# Fetch HuggingFace token from Secrets Manager
echo "Fetching HuggingFace token from Secrets Manager..."
HF_TOKEN=\$(aws secretsmanager get-secret-value \
    --secret-id llm-tuning-lab/huggingface-token \
    --region $AWS_DEFAULT_REGION \
    --query SecretString \
    --output text)

# Run training with HF_TOKEN
docker run --gpus all --rm \
    -v /workspace/data:/workspace/data:ro \
    -v /workspace/output:/workspace/output \
    -v /workspace/checkpoints:/workspace/checkpoints \
    -e AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION \
    -e LLM_DATA__DATA_DIR=/workspace/data \
    -e LLM_TRAINING__OUTPUT_DIR=/workspace/checkpoints \
    -e HF_TOKEN=\$HF_TOKEN \
    $ECR_REPOSITORY_URL:$DOCKER_IMAGE_TAG \
    $TRAINING_COMMAND

EXIT_CODE=\$?

# End timestamp
END_TIME=\$(date +%s)
DURATION=\$((END_TIME - START_TIME))
DURATION_MIN=\$((DURATION / 60))

echo "========================================"
echo "Training Run Completed: \$(date)"
echo "Duration: \$DURATION_MIN minutes"
echo "Exit Code: \$EXIT_CODE"
echo "========================================"

# Sync outputs to S3
if [ \$EXIT_CODE -eq 0 ]; then
    echo "Training successful, syncing outputs to S3..."
    aws s3 sync /workspace/checkpoints/ s3://$OUTPUTS_BUCKET/runs/\$RUN_ID/checkpoints/ --quiet
    aws s3 sync /workspace/output/ s3://$OUTPUTS_BUCKET/runs/\$RUN_ID/output/ --quiet
    
    # Create success marker
    echo "Training completed successfully at \$(date)" | \
        aws s3 cp - s3://$OUTPUTS_BUCKET/runs/\$RUN_ID/SUCCESS
    
    echo "Outputs synced to s3://$OUTPUTS_BUCKET/runs/\$RUN_ID/"
else
    echo "Training failed with exit code \$EXIT_CODE"
    
    # Upload logs anyway for debugging
    aws s3 sync /workspace/output/ s3://$OUTPUTS_BUCKET/runs/\$RUN_ID/output-failed/ --quiet || true
    
    # Create failure marker
    echo "Training failed at \$(date) with exit code \$EXIT_CODE" | \
        aws s3 cp - s3://$OUTPUTS_BUCKET/runs/\$RUN_ID/FAILURE
fi

# Auto-shutdown if enabled
if [ "$AUTO_SHUTDOWN" = "true" ]; then
    echo "Auto-shutdown enabled, terminating instance in 5 minutes..."
    sleep 300
    
    # Get instance ID from metadata
    INSTANCE_ID=\$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    echo "Terminating instance: \$INSTANCE_ID"
    
    # Self-terminate
    aws ec2 terminate-instances --instance-ids \$INSTANCE_ID --region $AWS_DEFAULT_REGION
fi

exit \$EXIT_CODE
EOF

chmod +x /workspace/run_training.sh

# Run training in tmux session (so you can attach if needed)
echo "Starting training in tmux session..."
tmux new-session -d -s training "cd /workspace && ./run_training.sh 2>&1 | tee /var/log/training.log"

echo "========================================"
echo "Training Instance Setup Complete: $(date)"
echo "Training is running in tmux session 'training'"
echo "To monitor: tmux attach -t training"
echo "To view logs: tail -f /var/log/training.log"
echo "========================================"


