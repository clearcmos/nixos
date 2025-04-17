{ config, lib, pkgs, ... }:

with lib;

let
  # Import env helper functions from configuration.nix
  envFile = "/etc/nixos/.env";
  envExists = builtins.pathExists envFile;
  
  loadEnvFile = file:
    let
      content = builtins.readFile file;
      # Handle empty content case
      lines = if content == "" then [] else 
              builtins.filter (l: l != "" && builtins.substring 0 1 l != "#")
                            (lib.splitString "\n" content);
      parseLine = l:
        let
          parts = lib.splitString "=" l;
          key = builtins.head parts;
          value = builtins.concatStringsSep "=" (builtins.tail parts);
        in { name = key; value = value; };
      envVars = builtins.listToAttrs (map parseLine lines);
    in envVars;

  env = if envExists then loadEnvFile envFile else {};
  
  # Function to get a value from the env file with a default
  getEnv = name: default: if builtins.hasAttr name env
                        then env.${name}
                        else default;
                        
  # Extract Cloudflare credentials from environment
  cfApiToken = getEnv "CLOUDFLARE_API_TOKEN" "";
  cfZoneId = getEnv "CLOUDFLARE_ZONE_ID" "";
  cfEmail = getEnv "CLOUDFLARE_EMAIL" "";
  
  # Get base domain from .env (or hardcode bedrosn.com if not present)
  baseDomain = getEnv "DOMAIN" "bedrosn.com";
  
  # Function to create Cloudflare DNS script
  mkCloudflareScript = subdomain: ''
    # Create a temporary script file for Cloudflare DNS operations
    cat > /tmp/cloudflare_dns_${subdomain}.sh << 'EOF'
#!/bin/bash

# Source environment variables
source /etc/nixos/.env

SUBDOMAIN="$1"
DOMAIN="$2"
RECORD_NAME="$SUBDOMAIN.$DOMAIN"

echo "Checking DNS for $RECORD_NAME..."

# Check if a DNS record already exists
response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records?type=CNAME&name=$RECORD_NAME" \
    -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json")

# Check if record exists
record_count=$(echo "$response" | jq -r '.result | length')

if [ "$record_count" = "0" ]; then
    echo "DNS record does not exist, creating now..."
    
    # Create the DNS record
    create_response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
        -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"CNAME\",\"name\":\"$SUBDOMAIN\",\"content\":\"$DOMAIN\",\"ttl\":1,\"proxied\":false}")
    
    success=$(echo "$create_response" | jq -r '.success')
    
    if [ "$success" = "true" ]; then
        echo "Successfully created DNS record for $RECORD_NAME"
    else
        error=$(echo "$create_response" | jq -r '.errors[0].message')
        echo "Failed to create DNS record: $error"
    fi
else
    echo "DNS record for $RECORD_NAME already exists."
fi
EOF

    # Make the script executable
    chmod +x /tmp/cloudflare_dns_${subdomain}.sh
    
    # Run the script with parameters
    /tmp/cloudflare_dns_${subdomain}.sh "${subdomain}" "${baseDomain}"
    
    # Clean up
    rm /tmp/cloudflare_dns_${subdomain}.sh
  '';
  
  # Function to check and create certificates
  mkCertScript = subdomain: ''
    SUBDOMAIN="${subdomain}"
    DOMAIN="${baseDomain}"
    CERT_DIR="/var/lib/acme/$SUBDOMAIN.$DOMAIN"
    
    if [ ! -d "$CERT_DIR" ] || [ ! -f "$CERT_DIR/fullchain.pem" ]; then
      echo "Certificate for $SUBDOMAIN.$DOMAIN not found. Will need to generate."
      
      # Mark this domain for certificate generation
      mkdir -p /tmp/missing-certs
      echo "$SUBDOMAIN.$DOMAIN" >> /tmp/missing-certs/domains.txt
    fi
  '';
  
  # Extract all subdomains from virtualHosts configurations
  # This returns a list of subdomain strings
  allSubdomains = let
    # Find all virtualHosts that use a domain ending with baseDomain
    matchingHosts = filterAttrs 
      (name: _: (lib.hasSuffix baseDomain name) && (lib.hasPrefix "." (lib.removePrefix baseDomain name)))
      config.services.nginx.virtualHosts;
    
    # Extract just the subdomain part
    getSubdomain = domain: 
      lib.removeSuffix ("." + baseDomain) domain;
  in
    mapAttrsToList (name: _: getSubdomain name) matchingHosts;

in {
  # ACME/certificate configuration
  security.acme = {
    acceptTerms = true;
    defaults = {
      # Use email from .env file
      email = "${getEnv "MAIN_EMAIL" "admin@bedrosn.com"}";
      group = "nginx";  # Set nginx as the group for all certificates
      # Use DNS validation with Cloudflare by default
      dnsProvider = "cloudflare";
      credentialsFile = "/run/secrets/cloudflare-credentials";
      dnsPropagationCheck = true;
      # Critical fix: explicitly set webroot to null to avoid conflict with dnsProvider
      webroot = null;
    };
    
    certs = {
      # Since we defined defaults with dnsProvider and credentialsFile,
      # we can simplify these definitions
      "auth.bedrosn.com" = { };
      "jellyfin.bedrosn.com" = { };
      "bedrosn.com" = { };
      "diskvue.bedrosn.com" = { };
      "git.bedrosn.com" = { };
      "overseerr.bedrosn.com" = { };
      "n8n.bedrosn.com" = { };
      "ha.bedrosn.com" = { };
      "base.bedrosn.com" = { };
      "cleaning.bedrosn.com" = { };
      "dash.bedrosn.com" = { };
      "dsm.bedrosn.com" = { };
      "sab.bedrosn.com" = { };
      "portainer.bedrosn.com" = { };
      "files.bedrosn.com" = { };
      "radarr.bedrosn.com" = { };
      "sonarr.bedrosn.com" = { };
      "photos.bedrosn.com" = { };
      "cockpit.bedrosn.com" = { };
      
      # Add certificates for glances and scrutiny
      "glances.bedrosn.com" = { };
      "scrutiny.bedrosn.com" = { };
      
      # The new site-specific domains will be automatically defined by their respective site modules
    };
  };
  
  # Install required tools
  environment.systemPackages = with pkgs; [
    curl
    jq
    certbot
  ];
  
  # Setup Cloudflare credentials for ACME
  system.activationScripts.setupCloudflareCredentials = ''
    mkdir -p /run/secrets
    if [ ! -f /run/secrets/cloudflare-credentials ] || ! grep -q "dns_cloudflare_api_token" /run/secrets/cloudflare-credentials; then
      echo "Creating Cloudflare credentials file for ACME..."
      cat > /run/secrets/cloudflare-credentials << EOF
dns_cloudflare_email = ${cfEmail}
dns_cloudflare_api_token = ${cfApiToken}
EOF
      chmod 600 /run/secrets/cloudflare-credentials
    fi
  '';
  
  # Create a script to check and ensure all subdomains are properly configured in Cloudflare and have certificates
  system.activationScripts.ensureSubdomains = ''
    echo "Checking subdomains for ${baseDomain}..."
    
    # Clean up any previous files
    rm -rf /tmp/missing-certs
    mkdir -p /tmp/missing-certs
    
    # Check subdomains and create DNS entries if needed
    ${concatMapStrings (subdomain: ''
      # Process ${subdomain}
      echo "Checking subdomain: ${subdomain}"
      ${mkCloudflareScript subdomain}
      ${mkCertScript subdomain}
    '') allSubdomains}
    
    # If any domains need certificates, automatically create them
    if [ -f "/tmp/missing-certs/domains.txt" ] && [ -s "/tmp/missing-certs/domains.txt" ]; then
      echo ""
      echo "=============================================="
      echo "ATTENTION: The following domains need certificates:"
      cat /tmp/missing-certs/domains.txt
      
      # Create a script to set up certificates
      cat > /tmp/setup_certificates.sh << 'CERTEOF'
#!/bin/bash

# Source environment variables
source /etc/nixos/.env

# Create certificates for missing domains
if [ -f "/tmp/missing-certs/domains.txt" ]; then
  DOMAINS=$(cat /tmp/missing-certs/domains.txt)
  for DOMAIN in $DOMAINS; do
    echo "Setting up certificate for $DOMAIN..."
    
    # First ensure DNS record exists
    SUBDOMAIN=$(echo "$DOMAIN" | cut -d'.' -f1)
    BASE_DOMAIN="bedrosn.com"
    
    # Check if DNS record exists
    DNS_CHECK=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records?type=CNAME&name=$DOMAIN" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json")
    
    DNS_EXISTS=$(echo "$DNS_CHECK" | jq -r '.result | length')
    
    if [ "$DNS_EXISTS" = "0" ]; then
      echo "Creating DNS record for $DOMAIN..."
      curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"CNAME\",\"name\":\"$SUBDOMAIN\",\"content\":\"$BASE_DOMAIN\",\"ttl\":1,\"proxied\":false}"
      
      # Wait for DNS propagation
      echo "Waiting for DNS propagation (30 seconds)..."
      sleep 30
    fi
    
    # Create directory for certificate
    mkdir -p "/var/lib/acme/$DOMAIN"
    
    # Now create the certificate using certbot
    certbot certonly --webroot -w /var/lib/acme/acme-challenge -d "$DOMAIN" --email "$MAIN_EMAIL" --agree-tos --non-interactive
    
    # Copy certificates to the right location
    if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
      cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "/var/lib/acme/$DOMAIN/"
      cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "/var/lib/acme/$DOMAIN/"
      cp "/etc/letsencrypt/live/$DOMAIN/chain.pem" "/var/lib/acme/$DOMAIN/"
      cp "/etc/letsencrypt/live/$DOMAIN/cert.pem" "/var/lib/acme/$DOMAIN/"
      
      # Set proper permissions
      chmod -R 755 "/var/lib/acme/$DOMAIN"
      chmod 640 "/var/lib/acme/$DOMAIN/privkey.pem"
      
      echo "Certificate for $DOMAIN created successfully"
    else
      echo "Failed to create certificate for $DOMAIN"
    fi
  done
fi
CERTEOF
      
      # Make script executable
      chmod +x /tmp/setup_certificates.sh
      
      # Run the script
      echo "Running certificate setup script..."
      /tmp/setup_certificates.sh
      
      echo "Certificate setup complete."
      echo "=============================================="
    fi
  '';
}