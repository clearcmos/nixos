#!/bin/bash
# Script to transfer Let's Encrypt certificates from Debian to NixOS
# Usage: sudo ./transfer-certificates.sh /path/to/extracted/letsencrypt-backup

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

if [ -z "$1" ]; then
  echo "Usage: $0 /path/to/extracted/letsencrypt-backup"
  exit 1
fi

BACKUP_PATH="$1"
LETSENCRYPT_PATH="${BACKUP_PATH}/etc/letsencrypt"
ACME_PATH="/var/lib/acme"

# Ensure the ACME directory exists
mkdir -p "${ACME_PATH}"

# Find all domains with live certificates
echo "Discovering domains with certificates..."
DOMAINS=$(find "${LETSENCRYPT_PATH}/live" -maxdepth 1 -mindepth 1 -type d -exec basename {} \;)

if [ -z "$DOMAINS" ]; then
  echo "No domains found in ${LETSENCRYPT_PATH}/live"
  exit 1
fi

echo "Found domains: $DOMAINS"

# Process each domain
for DOMAIN in $DOMAINS; do
  echo "Processing domain: $DOMAIN"
  
  # Create directory for this domain
  mkdir -p "${ACME_PATH}/${DOMAIN}"
  
  # Copy certificate files
  echo "Copying certificate files for $DOMAIN"
  cp "${LETSENCRYPT_PATH}/live/${DOMAIN}/fullchain.pem" "${ACME_PATH}/${DOMAIN}/"
  cp "${LETSENCRYPT_PATH}/live/${DOMAIN}/privkey.pem" "${ACME_PATH}/${DOMAIN}/"
  cp "${LETSENCRYPT_PATH}/live/${DOMAIN}/chain.pem" "${ACME_PATH}/${DOMAIN}/"
  cp "${LETSENCRYPT_PATH}/live/${DOMAIN}/cert.pem" "${ACME_PATH}/${DOMAIN}/"
  
  # Set permissions (NixOS handles users differently)
  chmod -R 755 "${ACME_PATH}/${DOMAIN}"
  chmod 640 "${ACME_PATH}/${DOMAIN}/privkey.pem"
  
  echo "Certificates for $DOMAIN transferred successfully"
  echo "------------------------------------------------"
  echo "Add the following to your NixOS configuration:"
  echo
  echo "security.acme.certs.\"${DOMAIN}\" = {"
  echo "  directory = \"${ACME_PATH}/${DOMAIN}\";"
  echo "  # Uncomment and update the following when ready for NixOS-managed renewal:"
  echo "  # email = \"your-email@example.com\";"
  echo "  # webroot = \"/var/lib/acme/acme-challenge\";"
  echo "  # extraDomainNames = [];"
  echo "};"
  echo
  echo "And for your nginx virtualHost:"
  echo
  echo "services.nginx.virtualHosts.\"${DOMAIN}\" = {"
  echo "  forceSSL = true;"
  echo "  useACMEHost = \"${DOMAIN}\";"
  echo "  # ... other configuration ..."
  echo "};"
  echo "------------------------------------------------"
done

echo "Certificate transfer complete!"
echo "Now update your NixOS configuration accordingly and run 'nixos-rebuild switch'"