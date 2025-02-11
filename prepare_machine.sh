#!/bin/bash
#
# Exmaple Usage: sh prepare_machine.sh.sh data-analyzer prod
#

set -e

APP_NAME="$1"
ENV="$2"


if ! grep -q "^ENV=" /etc/environment; then
echo "Environment=$ENV" >> /etc/environment
echo "ENV=$ENV" >> /etc/environment
echo "APP_NAME=$APP_NAME" >> /etc/environment
fi

# Prepare directories
# sudo mkdir -p /mnt/shared-efs || { echo "Failed to create directory"; exit 1; }

# --- 1. Install necessary tools
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -y || { echo "Failed to update apt repositories"; exit 1; }
sudo apt-get install -y zip unzip || { echo "Failed to install packages"; exit 1; }

# Create and configure /opt/getint
sudo mkdir -p /opt/getint || { echo "Failed to create /opt/getint"; exit 1; }
sudo chown -R ubuntu:ubuntu /opt/getint || { echo "Failed to change ownership"; exit 1; }

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf awscliv2.zip aws

# --- 2. DEPLOYMENT SCRIPT
# Create the /opt/getint directory and place the deployment script
sudo mkdir -p /opt/getint
sudo chown -R ubuntu:ubuntu /opt/getint

cat <<'SCRIPT' > /opt/getint/deployment.sh
#!/bin/bash
set -e

ACTION="$1"

S3_BUCKET="s3://getint-ci-artifacts/$APP_NAME/$ENV/$APP_NAME-latest.zip"
LOCAL_DIR="/opt/getint/$APP_NAME"

if ! aws configure list | grep -q 'shared-credentials-file'; then
  echo "AWSCLI is not configured. Run 'aws configure'"
  exit 1
fi

case "$ACTION" in
  upgrade)
      echo "Starting upgrade process for $APP_NAME on $(hostname)"

      mkdir -p "$LOCAL_DIR"
      cd "$LOCAL_DIR"

      echo "Downloading the latest version from S3..."
      aws s3 cp "${S3_BUCKET}" "${LOCAL_DIR}/latest-version.zip"

      if [ -d "package" ]; then
          cd package
          echo "Stopping running containers..."
          if docker-compose down; then
              echo "Containers stopped successfully."
              cd "${LOCAL_DIR}"
          else
              echo "Failed to stop containers. Exiting."
              exit 1
          fi
      else
          echo "No existing package directory found. Skipping container shutdown."
      fi

      cd "${LOCAL_DIR}"
      if unzip -o "latest-version.zip" -d "${LOCAL_DIR}/"; then
          echo "Unzip completed successfully."
      else
          echo "Unzip failed but most probably files were unzipped (issue with ..). Check the zip file."
      fi

      echo "Starting new deployment..."
      cd package
      ./run.sh --env aws

      echo "Upgrade completed successfully."
      ;;
  stop)
      echo "Stopping containers for $APP_NAME"
      if [ -d "${LOCAL_DIR}/package" ]; then
          cd "${LOCAL_DIR}/package"
          docker-compose down
          echo "Containers stopped successfully."
      else
          echo "No running containers found. Skipping."
      fi
      ;;
  start)
      echo "Starting application for $APP_NAME"
      if [ -d "${LOCAL_DIR}/package" ]; then
          cd "${LOCAL_DIR}/package"
          docker-compose down
          ./run.sh --env aws
          echo "Application started successfully."
      else
          echo "Package directory not found. Please upgrade first."
          exit 1
      fi
      ;;
  destroy)
      read -p "Type 'destroy' to confirm: " CONFIRM
      if [[ "${CONFIRM}" != "destroy" ]]; then
          echo "Aborting destruction process."
          exit 1
      fi
      cd "${LOCAL_DIR}/package"
      docker-compose down --rmi all --volumes
      cd /opt/getint/
      rm -rf "${LOCAL_DIR}/package"
      ;;
  *)
      echo "Usage: $0 {upgrade|stop|start}"
      exit 1
      ;;
esac
SCRIPT

chmod +x /opt/getint/deployment.sh

# 3. INSTALL DOCKER & DOCKER-COMPOSE
sudo apt-get install -y \
ca-certificates \
curl \
gnupg \
lsb-release
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo echo \  \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
$(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo docker --version
sudo docker compose version
sudo chown ubuntu:docker /var/run/docker.sock
sudo usermod -aG docker ubuntu
sudo apt-get install -y docker-compose
sudo systemctl start docker

sudo apt-get install jq wget -y 

sudo chmod -R 777 /opt/getint
cd /opt/getint
mkdir data
chmod -R 777 /opt/getint/data

# Place file in getint folder that machine was setup ok
touch /opt/getint/MACHINE_SETUP_OK

