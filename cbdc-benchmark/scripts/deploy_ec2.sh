#!/usr/bin/env bash
# ============================================================
# Deploy CBDC Benchmark from AWS CloudShell → EC2
# Run this ENTIRE script from AWS CloudShell (paste & execute)
# ============================================================
set -euo pipefail

# ── Configuration ────────────────────────────────────────────
INSTANCE_TYPE="c5.4xlarge"         # 16 vCPU, 32GB RAM
AMI_ID="ami-0c02fb55956c7d316"    # Amazon Linux 2023 (us-east-1)
                                   # Update per region: https://aws.amazon.com/amazon-linux-2/
KEY_NAME="cbdc-benchmark-key"
SG_NAME="cbdc-benchmark-sg"
REPO_URL="https://github.com/YOUR_ORG/cbdc-benchmark.git"  # UPDATE THIS
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
DATA_BUCKET=""   # Optional: s3://your-bucket/realtime_txn_dataset.csv

echo "======================================================"
echo "  CBDC Benchmark - EC2 Deployment via CloudShell"
echo "  Region: ${REGION} | Instance: ${INSTANCE_TYPE}"
echo "======================================================"

# ── Create Key Pair ──────────────────────────────────────────
if ! aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$REGION" &>/dev/null; then
    echo "Creating key pair: $KEY_NAME"
    aws ec2 create-key-pair \
        --key-name "$KEY_NAME" \
        --region "$REGION" \
        --query 'KeyMaterial' \
        --output text > "${KEY_NAME}.pem"
    chmod 400 "${KEY_NAME}.pem"
    echo "Key saved: ${KEY_NAME}.pem"
fi

# ── Create Security Group ────────────────────────────────────
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=is-default,Values=true" \
    --region "$REGION" \
    --query 'Vpcs[0].VpcId' \
    --output text)

SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${SG_NAME}" \
    --region "$REGION" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "")

if [[ "$SG_ID" == "None" || -z "$SG_ID" ]]; then
    echo "Creating security group: $SG_NAME"
    SG_ID=$(aws ec2 create-security-group \
        --group-name "$SG_NAME" \
        --description "CBDC Benchmark Security Group" \
        --vpc-id "$VPC_ID" \
        --region "$REGION" \
        --query 'GroupId' \
        --output text)
    
    # Allow SSH
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp --port 22 \
        --cidr 0.0.0.0/0 \
        --region "$REGION"
    
    echo "Security group created: $SG_ID"
fi

# ── User Data Script (runs on EC2 at first boot) ─────────────
USER_DATA=$(cat <<'USERDATA'
#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/cbdc-bootstrap.log) 2>&1

echo "=== CBDC Benchmark Bootstrap ==="
date

# Install dependencies
dnf update -y
dnf install -y docker git python3 python3-pip jq curl

# Docker
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

# Docker Compose
COMPOSE_VER=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)
curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VER}/docker-compose-linux-x86_64" \
    -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Node.js 18
curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
dnf install -y nodejs

# Python packages
pip3 install matplotlib pandas numpy jinja2 requests

# Clone repo
cd /home/ec2-user
git clone __REPO_URL__ cbdc-benchmark
chown -R ec2-user:ec2-user cbdc-benchmark

# Setup data directory
mkdir -p /data /results
chown ec2-user:ec2-user /data /results

# Download dataset if S3 bucket provided
if [[ -n "__DATA_BUCKET__" ]]; then
    aws s3 cp "__DATA_BUCKET__" /data/realtime_txn_dataset.csv || true
fi

# Create symlink so run.sh can find data and results
ln -sf /data /home/ec2-user/cbdc-benchmark/data
ln -sf /results /home/ec2-user/cbdc-benchmark/results

# Install Node deps
cd /home/ec2-user/cbdc-benchmark
sudo -u ec2-user npm install
sudo -u ec2-user npx caliper bind --caliper-bind-sut ethereum:latest

echo "=== Bootstrap Complete ==="
echo "Run: sudo -u ec2-user bash /home/ec2-user/cbdc-benchmark/run.sh"
USERDATA
)

# Inject variables
USER_DATA="${USER_DATA/__REPO_URL__/${REPO_URL}}"
USER_DATA="${USER_DATA/__DATA_BUCKET__/${DATA_BUCKET}}"

# ── Launch EC2 Instance ──────────────────────────────────────
echo "Launching EC2 instance..."
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --user-data "$USER_DATA" \
    --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":60,"VolumeType":"gp3","Iops":3000,"Throughput":125}}]' \
    --instance-initiated-shutdown-behavior terminate \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=cbdc-benchmark},{Key=Project,Value=CBDC}]' \
    --region "$REGION" \
    --query 'Instances[0].InstanceId' \
    --output text)

echo "Instance launched: $INSTANCE_ID"

# ── Wait for instance ────────────────────────────────────────
echo "Waiting for instance to be running..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"

PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

echo ""
echo "════════════════════════════════════════════════════════"
echo "  Instance ready!"
echo "  ID:       $INSTANCE_ID"
echo "  IP:       $PUBLIC_IP"
echo "  Region:   $REGION"
echo ""
echo "  SSH:      ssh -i ${KEY_NAME}.pem ec2-user@${PUBLIC_IP}"
echo ""
echo "  Monitor bootstrap: ssh ... 'tail -f /var/log/cbdc-bootstrap.log'"
echo ""
echo "  After bootstrap (~5 min), run benchmark:"
echo "  ssh ... 'cd ~/cbdc-benchmark && bash run.sh'"
echo ""
echo "  Copy results back:"
echo "  scp -r -i ${KEY_NAME}.pem ec2-user@${PUBLIC_IP}:/results ./benchmark-results/"
echo "════════════════════════════════════════════════════════"

# Save connection info
cat > cbdc-benchmark-connection.txt <<EOF
Instance ID: $INSTANCE_ID
Public IP:   $PUBLIC_IP
Region:      $REGION
Key:         ${KEY_NAME}.pem

SSH: ssh -i ${KEY_NAME}.pem ec2-user@${PUBLIC_IP}
Run: cd ~/cbdc-benchmark && bash run.sh
Results: scp -r -i ${KEY_NAME}.pem ec2-user@${PUBLIC_IP}:/results ./
EOF

echo "Connection info saved: cbdc-benchmark-connection.txt"
