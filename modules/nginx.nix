{ config, lib, pkgs, ... }:

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
                         
  # Extract MaxMind credentials from environment
  maxmindAccountId = getEnv "MAXMIND_ACCOUNT_ID" "";
  maxmindLicenseKey = getEnv "MAXMIND_LICENSE_KEY" "";
  
  # Extract Router IP from environment
  routerIp = getEnv "ROUTER_IP" "192.168.1.1";
  
  # Extract whitelisted country codes from environment
  # Expected format: "CA TN US" (space-separated country codes)
  whitelistedCountryCodes = lib.splitString " " (getEnv "WHITELISTED_COUNTRY_CODES" "US");
  
  # Format country codes for the nginx config
  formatCountryCodes = codes:
    lib.concatMapStrings (code: "        ${code} yes;\n") codes;
  
  whitelistFormatted = formatCountryCodes whitelistedCountryCodes;
  
  # GeoIP editions to download
  geoipEditions = [
    "GeoLite2-ASN"
    "GeoLite2-City"
    "GeoLite2-Country"
  ];

  # Get default email for Let's Encrypt
  certbotEmail = getEnv "EMAIL_ADDRESS" "";

in {
  # Ensure this module is only activated when credentials are provided
  config = {
    # Install required packages
    environment.systemPackages = with pkgs; [
      curl
      geoipupdate
      jq
      wget
      nginx # Added nginx so the command is available in PATH
      certbot # Added certbot so it's available in PATH
    ];

    # Configure and enable nginx
    services.nginx = {
      enable = true;
      
      # Disable built-in recommended settings to use our own
      recommendedGzipSettings = false;
      recommendedOptimisation = false;
      recommendedProxySettings = false;
      recommendedTlsSettings = false;
      
      # Load GeoIP2 module
      package = pkgs.nginx.override {
        modules = [ pkgs.nginxModules.geoip2 ];
      };
      
      # Custom nginx configuration that exactly matches the Debian setup
      config = ''
        # NixOS sets user automatically, so we don't need "user www-data;" here
        worker_processes auto;
        # NixOS sets pid file location, so we don't need "pid /run/nginx.pid;" here
        error_log /var/log/nginx/error.log;
        
        events {
            worker_connections 768;
        }
        
        http {
            sendfile on;
            tcp_nopush on;
            types_hash_max_size 2048;
            server_tokens off;
            
            include ${pkgs.nginx}/conf/mime.types;
            default_type application/octet-stream;
            
            ssl_protocols TLSv1.2 TLSv1.3;
            ssl_prefer_server_ciphers on;
            
            log_format geoip_log '$remote_addr - $remote_user [$time_local] '
                               '"$request" $status $body_bytes_sent '
                               '"$http_referer" "$http_user_agent" '
                               '"$geoip2_data_country_code"';
            
            access_log /var/log/nginx/access.log geoip_log;
            
            gzip on;
            
            # Path to GeoIP database (different from Debian, uses NixOS location)
            geoip2 /var/lib/GeoIP/GeoLite2-Country.mmdb {
                $geoip2_data_country_code country iso_code;
            }
            
            map $geoip2_data_country_code $allowed_country {
                default no;
${whitelistFormatted}
            }
            
            geo $exclusions {
                default 0;
                ${routerIp} 1;
            }
            
            limit_req_zone $binary_remote_addr zone=mylimit:10m rate=10r/s;
            
            server {
                location / {
                    limit_req zone=mylimit burst=20 nodelay;
                }
            }
            
            include /etc/nginx/conf.d/*.conf;
            include /etc/nginx/sites-enabled/*;
        }
      '';
    };

    # Configure the certbot service
    security.acme = {
      acceptTerms = true;
      defaults.email = certbotEmail;

      certs = {};  # Specific certificates will be defined here or in host configs
    };

    # Create shared SSL parameters for nginx
    system.activationScripts.setupNginxSslParams = ''
      mkdir -p /etc/nginx/ssl
      if [ ! -f /etc/nginx/ssl/options-ssl-nginx.conf ]; then
        cat > /etc/nginx/ssl/options-ssl-nginx.conf << 'EOL'
# This file contains important security parameters. If you modify this file
# manually, Certbot will be unable to automatically provide future security
# updates. Instead, Certbot will preserve this file as is and mark it as managed.
# See options-ssl-nginx.conf.dpkg-dist for a more verbose version of this file.

ssl_session_cache shared:le_nginx_SSL:10m;
ssl_session_timeout 1440m;
ssl_session_tickets off;

ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_ciphers "EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH";
ssl_ecdh_curve secp384r1;

ssl_stapling on;
ssl_stapling_verify on;

add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload";
add_header X-Frame-Options DENY;
add_header X-Content-Type-Options nosniff;
add_header X-XSS-Protection "1; mode=block";
EOL
        chmod 644 /etc/nginx/ssl/options-ssl-nginx.conf
      fi

      # Create DH parameters (this might take some time on first run)
      if [ ! -f /etc/nginx/ssl/ssl-dhparams.pem ]; then
        echo "Generating DH parameters, this might take a while..."
        ${pkgs.openssl}/bin/openssl dhparam -out /etc/nginx/ssl/ssl-dhparams.pem 2048
        chmod 644 /etc/nginx/ssl/ssl-dhparams.pem
      fi
    '';
    
    # Setup MaxMind license key file securely during activation
    system.activationScripts.setupMaxMindKey = lib.mkIf (maxmindAccountId != "" && maxmindLicenseKey != "") ''
      mkdir -p /run/keys
      if [ ! -f /run/keys/maxmind_license_key ] || ! grep -q "${maxmindLicenseKey}" /run/keys/maxmind_license_key; then
        echo "${maxmindLicenseKey}" > /run/keys/maxmind_license_key
        chmod 600 /run/keys/maxmind_license_key
      fi
    '';
    
    # Configure GeoIP updates with the license key file
    services.geoipupdate = lib.mkIf (maxmindAccountId != "" && maxmindLicenseKey != "") {
      enable = true;
      interval = "weekly"; # Weekly updates
      settings = {
        AccountID = lib.toInt maxmindAccountId;
        LicenseKey = "/run/keys/maxmind_license_key";
        EditionIDs = geoipEditions;
      };
    };
    
    # Create necessary directories for nginx
    system.activationScripts.nginxDirs = ''
      mkdir -p /etc/nginx/conf.d
      mkdir -p /etc/nginx/sites-enabled
      mkdir -p /var/log/nginx
    '';
    
    # Firewall configuration - ports to open when firewall is enabled
    networking.firewall = {
      # Firewall is managed in configuration.nix
      # Just define allowed ports here for when it's enabled
      allowedTCPPorts = [ 80 443 ];
    };
  };
}