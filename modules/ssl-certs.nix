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
    SUBDOMAIN="${subdomain}"
    DOMAIN="${baseDomain}"
    RECORD_NAME="$SUBDOMAIN.$DOMAIN"
    API_TOKEN="${cfApiToken}"
    ZONE_ID="${cfZoneId}"
    EMAIL="${cfEmail}"
    
    # Check if record exists
    RECORD_EXISTS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=CNAME&name=$RECORD_NAME" \
      -H "X-Auth-Email: $EMAIL" \
      -H "Authorization: Bearer $API_TOKEN" \
      -H "Content-Type: application/json" | \
      ${pkgs.jq}/bin/jq -r '.result | length')
      
    if [ "$RECORD_EXISTS" = "0" ]; then
      echo "Creating DNS record for $RECORD_NAME..."
      curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
        -H "X-Auth-Email: $EMAIL" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"CNAME\",\"name\":\"$SUBDOMAIN\",\"content\":\"$DOMAIN\",\"ttl\":1,\"proxied\":false}" | \
        ${pkgs.jq}/bin/jq -r '.success'
    else
      echo "DNS record for $RECORD_NAME already exists."
    fi
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
      # Email is already defined in nginx.nix
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
      
      # Add the new site-specific domains that might not have certificates yet
      "scrutiny.bedrosn.com" = {
        directory = "/var/lib/acme/scrutiny.bedrosn.com";
      };
      
      "glances.bedrosn.com" = {
        directory = "/var/lib/acme/glances.bedrosn.com";
      };
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
    
    # If any domains need certificates, display instructions
    if [ -f "/tmp/missing-certs/domains.txt" ] && [ -s "/tmp/missing-certs/domains.txt" ]; then
      echo ""
      echo "=============================================="
      echo "ATTENTION: The following domains need certificates:"
      cat /tmp/missing-certs/domains.txt
      echo ""
      echo "You may need to run a command like:"
      echo "sudo certbot --nginx $(cat /tmp/missing-certs/domains.txt | xargs -I{} echo "-d {}")"
      echo "=============================================="
    fi
  '';
}