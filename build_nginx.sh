#!/bin/bash

# Exit immediately if a command exits with a non-zero status
# Treat unset variables as an error
# Print each command before executing
# Fail the pipeline if any command fails
set -euxo pipefail

# Update all system packages
echo "Updating system packages..."
sudo yum -y update

# Install nginx
echo "Installing nginx..."
sudo amazon-linux-extras enable nginx1    # Only needed for Amazon Linux 2
sudo yum -y install nginx

# Start nginx service
echo "Starting nginx service..."
sudo systemctl start nginx

# Enable nginx to start on boot
echo "Enabling nginx to start at boot..."
sudo systemctl enable nginx

echo "Nginx installation and setup complete."