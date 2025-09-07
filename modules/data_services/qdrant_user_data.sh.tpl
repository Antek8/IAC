#!/bin/bash
# Update packages and install EFS utilities
yum update -y
yum install -y amazon-efs-utils

# Mount the EFS file system
EFS_ID=${efs_id}
MOUNT_POINT="/opt/qdrant/storage"
mkdir -p $MOUNT_POINT
mount -t efs -o tls $EFS_ID:/ $MOUNT_POINT

# Configure Docker logging
cat <<'EOT' > /etc/docker/daemon.json
{
  "log-driver": "awslogs",
  "log-opts": {
    "awslogs-group": "${name}-qdrant-ec2-logs",
    "awslogs-region": "${region}",
    "awslogs-create-group": "true"
  }
}
EOT
systemctl restart docker

# Run Qdrant container, now using persistent EFS storage
docker run -d -p 6333:6333 -v $MOUNT_POINT:/qdrant/storage qdrant/qdrant:latest