#!/bin/bash

set -euxo pipefail

# Authenticate admin admin with Vault using AppRole.
vault read auth/approle/role/admin-role

# Read Vault policy for admin admin.
vault policy list
vault policy read admin-cert-policy

# Read the admin role-id
vault read auth/approle/role/admin-role/role-id

# Just in case I have to reauthenticate admin admin with Vault.
# vault write -f auth/approle/role/admin-role/secret-id
# In the admin admin
# echo "fe589c29-9cbc-2a05-b18b-9b54ba2e3e5" > /etc/vault-agent.d/secret_id | chmod 600 /etc/vault-agent.d/secret_id
# Restart the Vault agent on the admin admin to apply changes.
# sudo systemctl restart vault-agent

# Cat the admin admin's vault agent configuration file and admin-cert.tpl
cat /etc/vault-agent.d/vault-agent.hcl
cat /etc/vault-agent.d/admin-cert.tpl

# Enable the PKI secrets engine at the path "root_pki".
vault secrets enable -path=root_pki pki

# Tune root_pki to issue certificates with a maximum TTL of 10 years or 87600 hours.
vault secrets tune -max-lease-ttl=87600h root_pki

# This command doesn't produce an output. 
# Generate the root CA certificate and private key.
# Save the certificate to a file named vault-root-ca.crt.
# The -field=certificate option extracts the certificate from the command output.
# The common_name is set to "Vault Root CA" and the issuer_name is set to "vault-root-ca".
# The ttl is set to 87600 hours (10 years).
vault write -field=certificate root_pki/root/generate/internal \
    common_name="Vault Root CA" \
    issuer_name="vault-root-ca" \
    ttl=87600h > vault-root-ca.crt
# This generates a new self-signed CA certificate and private key.
# Vault automatically revokes the generated root at end of TTL or lease period.

# List the issuers and its keys
vault list root_pki/issuers

# Read the issuer with its ID and get certificate metadata
vault read root_pki/issuer/vault-root-ca

# Create a role for the root_pki CA.
# This allows for specifying an issuer when necessary.
# This also allows you to transition from one issuer to another.
# By referring to it by name
vault write root_pki/roles/admin \
    allow_subdomains=true \
    allow_ip_sans=true

# Configure the CA and CRL URLs.
vault write root_pki/config/urls \
    issuing_certificates="https://127.0.0.1:8200/v1/root_pki/ca" \
    crl_distribution_points="https://127.0.0.1:8200/v1/root_pki/crl"

# Generate an intermediate CA certificate.

vault secrets enable -path=pki_int pki

# Tune pki_int to issue certificates with 
# a maximum TTL of 5 years or 43800 hours.
vault secrets tune -max-lease-ttl=43800h pki_int

# Generate an intermediate and save the CSR to pki_intermediate.csr.
# This command doesn't produce an output.
vault write -format=json pki_int/intermediate/generate/internal \
    common_name="Vault Intermediate Authority" \
    issuer_name="vault-int-ca" \
    | jq -r '.data.csr' > pki_intermediate.csr

# Sign the intermediate CA with the root CA private key.
# Save the signed certificate to pki_intermediate.cert.pem.
# This command doesn't produce an output.
vault write -format=json root_pki/root/sign-intermediate \
> issuer_ref="vault-root-ca" \
> csr=@pki_intermediate.csr \
> format=pem_bundle ttl="43800h" \
> | jq -r '.data.certificate' > pki_intermediate.cert.pem

# After signing CSR, root CA returns signed certificate
# Import signed certificate back into Vault.
vault write pki_int/intermediate/set-signed certificate=@pki_intermediate.cert.pem

# Configure the pki_int CA and CRL URLs.
vault write pki_int/config/urls \
    issuing_certificates="http://127.0.0.1:8200/v1/pki_int/ca" \
    crl_distribution_points="http://127.0.0.1:8200/v1/pki_int/crl"

# Configure the cluster URLs for pki_int.
vault write pki_int/config/cluster \
    path=http://127.0.0.1:8200/v1/pki_int \
    aia_path=http://127.0.0.1:8200/v1/pki_int

# Create a role for the pki_int CA.
# This allows subdomains and IP SANs.
# This specifies the default issuer ref ID as the value of issuer_ref.
vault write pki_int/roles/admin \
    issuer_ref="$(vault read -field=default pki_int/config/issuers)" \
    allowed_domains="*.corp.internal" \
    allow_subdomains=true \
    allow_ip_sans=true \
    max_ttl="720h" 

# Request a certificate for the admin.
# This command requests a new certificate for the domain 
# based on the role created above.
vault write pki_int/issue/admin common_name="vault.corp.internal" ttl="24h"

# Run this command three times so you can revoke certificates next.

# List serial numbers of all issued certificates in pki_int.
vault list pki_int/certs

# Open certificate in admin admin to verify serial number.
openssl x509 -in /etc/admin/ssl/admin.pem -noout -text

# Revoke a certificate by its serial number.
vault write pki_int/revoke serial_number="SERIAL_NUMBER"

# Once certificate is revoked, restart vault agent on admin admin.
systemctl reload admin
sudo systemctl restart vault-agent

# Share information about the certificate within admin admin. 
openssl x509 -in /etc/admin/ssl/admin.pem -noout -text

# But the admin admin is still serving the old certificate.

# Rotate Root CA
vault write root_pki/root/rotate/internal \
    common_name="Vault Root CA 2.0" \
    issuer_name="vault-root-ca-2"

# Rotate Intermediate CA
vault write pki_int/intermediate/rotate/internal \
    common_name="Vault Intermediate Authority 2.0" \
    issuer_name="vault-int-ca-2"

# List the issuers and its keys for root_pki CA.
vault list root_pki/issuers

# Both root CA issuers are now enabled in the same PKI engine mount.
# While new root CA is generated, the old root CA is still valid.
# All later issuance from the mount uses the older root CA.

# Create a new role for the new root CA.
# This allows for specifying an issuer when necessary.
# Simple way to transition from one issuer to another.

# Set new default issuer for the root_pki CA.
vault write root_pki/root/replace -default="vault-root-ca-2"

# Sunset defunct root CA.
# This command means vault-root-ca can't issue new certificates.
# tail -n 5 is used to show the last 5 lines of the output.
vault write root_pki/issuer/vault-root-ca \
    issuer_name="vault-root-ca" \
    usage=read-only,crl-signing | tail -n 5

# Add certificate to Keychain to trust
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain vault-root-ca.pem

# Add intermediate CA to Keychain to trust
sudo security add-trusted-cert -d -r trustAsRoot -k /Library/Keychains/System.keychain vault-intermediate-ca.pem

vault write -f pki/tidy \	
	tidy_cert_store=true \
	tidy_revoked_certs=true \
	tidy_expired_issuers=true

# Demo Vault Agent with admin server.
# admin server is authenticated with Vault using AppRole.
# With AppRole, admin server has policies 
# vault read auth/approle/role/admin-role

# In Vault instance
# cat admin-cert-policy.hcl

# In admin instance
# This file is used by Vault Agent to authenticate with Vault.
# It contains the role ID and secret ID for the AppRole.
# The Vault Agent will use these credentials to authenticate with Vault and retrieve the certificate.
# The Vault Agent will also automatically renew the certificate before it expires.
# cat /etc/vault-agent.d/admin-agent.hcl

# This file is used by Vault Agent to render the certificate and key for admin.
# It contains the template for the certificate and key, which will be rendered by Vault Agent.
# The template will be rendered by Vault Agent and places the certs in the specified paths.
# The admin server will use these files to serve HTTPS traffic.
# cat /etc/vault-agent.d/admin-cert.tpl

# Read the admin role that's associated with the AppRole
# Also associated with the admin server. 
# vault read auth/approle/role/admin-role
# vault read auth/approle/role/admin-role/role-id
# vault write -f auth/approle/role/admin-role/secret-id

# Provide the role ID and secret ID to the admin server.
# echo "<REPLACE_WITH_ROLE_ID>" > /etc/vault-agent.d/role_id | chmod 600 /etc/vault-agent.d/role_id
# echo "<REPLACE_WITH_SECRET_ID>" > /etc/vault-agent.d/secret_id | chmod 600 /etc/vault-agent.d/secret_id