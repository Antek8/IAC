#!/bin/bash
yum update -y
yum install -y docker aws-cli
systemctl enable docker
systemctl start docker

echo "Agentic instance started"

# Assign template variables to shell variables for safer use
AGENTIC_IMAGE_URI="${agentic_image_uri}"
REGION="${region}"

# Check if an image URI was provided
if [ ! -z "$AGENTIC_IMAGE_URI" ]; then
  echo "Image URI is specified: $AGENTIC_IMAGE_URI"

  # Parse the ECR repository name and image tag from the URI
  REPO_NAME=$(echo $AGENTIC_IMAGE_URI | cut -d'/' -f2 | cut -d':' -f1)
  IMAGE_TAG=$(echo $AGENTIC_IMAGE_URI | cut -d':' -f2)

  # Check if the image tag exists in ECR before trying to pull it
  if aws ecr describe-images --repository-name $REPO_NAME --image-ids imageTag=$IMAGE_TAG --region $REGION > /dev/null 2>&1; then
    echo "Image found in ECR. Pulling and running container..."
    
    # Extract the ECR registry from the full image URI
    ECR_REGISTRY=$(echo $AGENTIC_IMAGE_URI | cut -d'/' -f1)
    
    # Log in to the ECR registry
    aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
    
    # Pull and run the container
    docker pull $AGENTIC_IMAGE_URI
    docker run -d --restart unless-stopped -p 80:8080 $AGENTIC_IMAGE_URI
  else
    echo "Image tag '$IMAGE_TAG' not found in ECR repository '$REPO_NAME'. Skipping container launch."
  fi
else
  echo "No image URI specified — skipping container launch."
fi
