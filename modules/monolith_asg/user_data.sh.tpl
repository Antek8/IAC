#!/bin/bash
yum update -y
yum install -y docker aws-cli
systemctl enable docker
systemctl start docker

echo "Frontend instance started"

# Assign the template variable to a shell variable
frontend_image_uri="${frontend_image_uri}"
region="${region}"

# Check if an image URI was provided
if [ ! -z "$frontend_image_uri" ]; then
  echo "Image URI is specified: $frontend_image_uri"

  # Log in to ECR, pull the image, and run the container
  aws ecr get-login-password --region ${region} | docker login --username AWS --password-stdin ${frontend_image_uri}
  docker pull ${frontend_image_uri}
  docker run -d -p 80:80 ${frontend_image_uri}
  
  echo "Container launch initiated."
else
  echo "No image URI specified — skipping container launch."
fi