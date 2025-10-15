#!/bin/bash
set -e
set -o pipefail

# Logging setup
LOGFILE="/var/log/training-setup-final.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "========================================"
echo "Training Instance Setup Started: $(date)"
echo "========================================"

# Environment variables
export AWS_DEFAULT_REGION="us-west-2"
export ECR_REPOSITORY_URL="451855940696.dkr.ecr.us-west-2.amazonaws.com/llm-tuning-lab-training"
export DOCKER_IMAGE_TAG="latest"
export TRAINING_BUCKET="llm-tuning-lab-training-data-training"
export OUTPUTS_BUCKET="llm-tuning-lab-outputs-training"
export TRAINING_COMMAND="python -m lab.train_lora --log-level INFO"
export AUTO_SHUTDOWN="true"
export DEBIAN_FRONTEND=noninteractive

# Update system
echo "Updating system packages..."
apt-get update -y
apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

# Install required packages (Docker already on Deep Learning AMI)
echo "Installing required packages..."
apt-get install -y jq unzip htop tmux || echo "Warning: Some packages already installed"

# Ensure Docker is running
echo "Ensuring Docker service is running..."
systemctl enable docker || true
systemctl start docker || true

# Install nvidia-docker2 (non-interactive)
echo "Installing nvidia-docker2..."
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
    tee /etc/apt/sources.list.d/nvidia-docker.list
apt-get update
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" nvidia-docker2
systemctl restart docker

# Verify GPU
echo "Verifying GPU availability..."
nvidia-smi

# Test nvidia-docker
echo "Testing nvidia-docker..."
docker run --rm --gpus all nvidia/cuda:11.0.3-base-ubuntu20.04 nvidia-smi

# Login to ECR
echo "Logging into ECR..."
aws ecr get-login-password --region $AWS_DEFAULT_REGION | \
    docker login --username AWS --password-stdin $ECR_REPOSITORY_URL

# Pull training image
echo "Pulling training image: $ECR_REPOSITORY_URL:$DOCKER_IMAGE_TAG"
docker pull $ECR_REPOSITORY_URL:$DOCKER_IMAGE_TAG

# Create workspace directories with proper permissions
echo "Creating workspace directories..."
mkdir -p /workspace/data /workspace/output /workspace/checkpoints
chown -R ubuntu:ubuntu /workspace

# Sync training data from S3 (as root, then fix permissions)
echo "Syncing training data from S3..."
if aws s3 ls s3://$TRAINING_BUCKET/ > /dev/null 2>&1; then
    aws s3 sync s3://$TRAINING_BUCKET/data/ /workspace/data/ --quiet
    chown -R ubuntu:ubuntu /workspace
    echo "Training data synced successfully ($(ls /workspace/data | wc -l) files)"
else
    echo "WARNING: Training bucket is empty or inaccessible"
fi

# Create training script
echo "Creating training script..."
cat > /workspace/run_training.sh << 'TRAINEOF'
#!/bin/bash
set -e

START_TIME=$(date +%s)
RUN_ID=$(date +%Y%m%d-%H%M%S)

echo "========================================="
echo "Training Run Started: $(date)"
echo "Run ID: $RUN_ID"
echo "========================================="

# Run training
docker run --gpus all --rm \
    -v /workspace/data:/workspace/data:ro \
    -v /workspace/output:/workspace/output \
    -v /workspace/checkpoints:/workspace/checkpoints \
    -e AWS_DEFAULT_REGION=us-west-2 \
    -e LLM_DATA__DATA_DIR=/workspace/data \
    -e LLM_TRAINING__OUTPUT_DIR=/workspace/checkpoints \
    451855940696.dkr.ecr.us-west-2.amazonaws.com/llm-tuning-lab-training:latest \
    python -m lab.train_lora --log-level INFO

EXIT_CODE=$?

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
DURATION_MIN=$((DURATION / 60))

echo "========================================="
echo "Training Run Completed: $(date)"
echo "Duration: $DURATION_MIN minutes"
echo "Exit Code: $EXIT_CODE"
echo "========================================="

if [ $EXIT_CODE -eq 0 ]; then
    echo "Training successful, syncing outputs to S3..."
    aws s3 sync /workspace/checkpoints/ s3://llm-tuning-lab-outputs-training/runs/$RUN_ID/checkpoints/ --region us-west-2 --quiet
    aws s3 sync /workspace/output/ s3://llm-tuning-lab-outputs-training/runs/$RUN_ID/output/ --region us-west-2 --quiet
    echo "Training completed successfully at $(date)" | \
        aws s3 cp - s3://llm-tuning-lab-outputs-training/runs/$RUN_ID/SUCCESS --region us-west-2
    echo "Outputs synced to s3://llm-tuning-lab-outputs-training/runs/$RUN_ID/"
else
    echo "Training failed with exit code $EXIT_CODE"
    aws s3 sync /workspace/output/ s3://llm-tuning-lab-outputs-training/runs/$RUN_ID/output-failed/ --region us-west-2 --quiet || true
    echo "Training failed at $(date) with exit code $EXIT_CODE" | \
        aws s3 cp - s3://llm-tuning-lab-outputs-training/runs/$RUN_ID/FAILURE --region us-west-2
fi

# Auto-shutdown
echo "Auto-shutdown enabled, terminating instance in 5 minutes..."
sleep 300
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
echo "Terminating instance: $INSTANCE_ID"
aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region us-west-2

exit $EXIT_CODE
TRAINEOF

chmod +x /workspace/run_training.sh
chown ubuntu:ubuntu /workspace/run_training.sh

# Start training in tmux as ubuntu user
echo "Starting training in tmux session..."
su - ubuntu -c "tmux new-session -d -s training 'cd /workspace && ./run_training.sh 2>&1 | tee /var/log/training.log'"

echo "========================================="
echo "Training Instance Setup Complete: $(date)"
echo "Training is running in tmux session 'training'"
echo "To monitor: sudo su - ubuntu -c 'tmux attach -t training'"
echo "To view logs: tail -f /var/log/training.log"
echo "========================================="

