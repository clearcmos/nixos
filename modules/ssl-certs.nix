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
  # Create a script to be run after the system is built
  # This avoids exposing the email in the Nix store
  system.activationScripts.createAcmeEmailScript = ''
    cat > /tmp/fix-acme-email.sh << 'EOF'
#!/bin/bash
# Script to fix ACME email addresses without exposing them in the Nix configuration

# Get the email from .env
if [ -f /etc/nixos/.env ]; then
  email=$(grep "^MAIN_EMAIL=" /etc/nixos/.env | cut -d'=' -f2)
  if [ -n "$email" ]; then
    echo "Setting ACME email to value from .env..."
    
    # Find acme service files
    for service in $(ls /etc/systemd/system/acme-*.service 2>/dev/null); do
      echo "Processing $service"
      
      # Replace empty email with actual email
      if grep -q -- \"--email ''\" \"$service\"; then
        echo "Updating email in $service"
        sed -i "s/--email ''/--email '$email'/g" "$service"
        
        # Reload the service
        systemctl daemon-reload
        
        # Attempt to restart the service
        service_name=$(basename "$service")
        systemctl try-restart "$service_name"
      fi
    done
  else
    echo "No email found in .env file"
  fi
else
  echo "No .env file found"
fi
EOF
    chmod +x /tmp/fix-acme-email.sh
    
    # Schedule this to run after the system is fully built
    echo "#!/bin/bash" > /etc/cron.d/fix-acme-email
    echo "@reboot root /tmp/fix-acme-email.sh" >> /etc/cron.d/fix-acme-email
    chmod 644 /etc/cron.d/fix-acme-email
  '';

  security.acme = {
    acceptTerms = true;
    defaults = {
      # Read from env but use a dummy value by default (avoids script errors)
      email = lib.mkDefault "acme@example.com";
      webroot = "/var/lib/acme/acme-challenge";
      group = "nginx";  # Set nginx as the group for all certificates
    };
    
    certs = {
      "auth.bedrosn.com" = {
        directory = "/var/lib/acme/auth.bedrosn.com";
      };
      
      "jellyfin.bedrosn.com" = {
        directory = "/var/lib/acme/jellyfin.bedrosn.com";
      };
      
      "bedrosn.com" = {
        directory = "/var/lib/acme/bedrosn.com";
      };
      
      "diskvue.bedrosn.com" = {
        directory = "/var/lib/acme/diskvue.bedrosn.com";
      };
      
      "git.bedrosn.com" = {
        directory = "/var/lib/acme/git.bedrosn.com";
      };
      
      "overseerr.bedrosn.com" = {
        directory = "/var/lib/acme/overseerr.bedrosn.com";
      };
      
      "n8n.bedrosn.com" = {
        directory = "/var/lib/acme/n8n.bedrosn.com";
      };
      
      "ha.bedrosn.com" = {
        directory = "/var/lib/acme/ha.bedrosn.com";
      };
      
      "base.bedrosn.com" = {
        directory = "/var/lib/acme/base.bedrosn.com";
      };
      
      "cleaning.bedrosn.com" = {
        directory = "/var/lib/acme/cleaning.bedrosn.com";
      };
      
      "dash.bedrosn.com" = {
        directory = "/var/lib/acme/dash.bedrosn.com";
      };
      
      "dsm.bedrosn.com" = {
        directory = "/var/lib/acme/dsm.bedrosn.com";
      };
      
      "sab.bedrosn.com" = {
        directory = "/var/lib/acme/sab.bedrosn.com";
      };
      
      "portainer.bedrosn.com" = {
        directory = "/var/lib/acme/portainer.bedrosn.com";
      };
      
      "files.bedrosn.com" = {
        directory = "/var/lib/acme/files.bedrosn.com";
      };
      
      "radarr.bedrosn.com" = {
        directory = "/var/lib/acme/radarr.bedrosn.com";
      };
      
      "sonarr.bedrosn.com" = {
        directory = "/var/lib/acme/sonarr.bedrosn.com";
      };
      
      "photos.bedrosn.com" = {
        directory = "/var/lib/acme/photos.bedrosn.com";
      };
      
      "cockpit.bedrosn.com" = {
        directory = "/var/lib/acme/cockpit.bedrosn.com";
      };
      
      # The new site-specific domains will be automatically defined by their respective site modules
    };
  };
  
  # Install required tools
  environment.systemPackages = with pkgs; [
    curl
    jq
    certbot
  ];
  
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