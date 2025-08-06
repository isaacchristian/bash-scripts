#!/bin/sh
# This script installs Vault Agent and sets up AppRole credentials.

# Exit immediately if a command exits with a non-zero status
# Treat unset variables as an error
# Print each command before executing
# Fail the pipeline if any command fails
set -euxo pipefail

# Download Vault Agent binary
echo "Downloading Vault Agent..."
VAULT_VERSION="1.18.5"
ARCH="amd64" # only if using x86_64
wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_${ARCH}.zip -O /tmp/vault.zip

# Unzip and install Vault Agent
echo "Installing Vault Agent..."
unzip /tmp/vault.zip -d /tmp
sudo install /tmp/vault /usr/local/bin/vault

# Clean up
rm -f /tmp/vault.zip /tmp/vault

# Set up Vault Agent AppRole credentials
echo "Setting up Vault Agent AppRole credentials..."
mkdir -p /etc/vault-agent.d

# This is a placeholder; you should replace it with actual role_id and secret_id
# echo "<REPLACE_WITH_ROLE_ID>" > /etc/vault-agent.d/role_id
# echo "<REPLACE_WITH_SECRET_ID>" > /etc/vault-agent.d/secret_id

chmod 600 /etc/vault-agent.d/role_id /etc/vault-agent.d/secret_id