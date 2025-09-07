#!/bin/bash
# Install necessary packages for Amazon Linux 2023
yum update -y
yum install -y git aws-cli jq

# Define app directory
APP_DIR="/opt/agentic"
mkdir -p $APP_DIR

# Fetch GitHub deploy key from Secrets Manager
aws secretsmanager get-secret-value --secret-id ${deploy_key_secret_arn} --region ${region} | jq -r '.SecretString' > /tmp/deploy_key
chmod 600 /tmp/deploy_key

# Configure SSH to use the deploy key for GitHub
cat <<EOT > /tmp/ssh_config
Host github.com
  HostName github.com
  IdentityFile /tmp/deploy_key
  StrictHostKeyChecking no
EOT
mkdir -p ~/.ssh
mv /tmp/ssh_config ~/.ssh/config
chmod 600 ~/.ssh/config

# Clone the repository (replace with your actual repo URL)
git clone git@github.com:your-org/your-agentic-repo.git $APP_DIR

# Fetch application secrets and run the application
# (This part depends on your application's specific setup process)
# For example:
# aws secretsmanager get-secret-value --secret-id ${db_secret_arn} --region ${region} | jq -r '.SecretString' > $APP_DIR/.env
# cd $APP_DIR
# ./start-application.sh