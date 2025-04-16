# Host-specific configuration for misc
{ config, lib, pkgs, ... }:

{
  # Enable flakes and nix-command
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  imports = [
    ../../modules/claude.nix
    ../../modules/nginx.nix
    ../../modules/cifs-mounts.nix
    # Removing custom scrutiny module - using built-in NixOS module instead
  ];
  
  # Enable Scrutiny SMART disk monitoring
  services.scrutiny = {
    enable = true;
    openFirewall = true;  # Open the firewall for the Scrutiny web interface
    package = pkgs.scrutiny;
    
    # Enable the collector
    collector.enable = true;
  };
  
  # Add NGINX virtual host for Scrutiny
  services.nginx.virtualHosts."scrutiny.${config.networking.hostName}.${config.networking.domain}" = {
    locations."/" = {
      proxyPass = "http://localhost:8080";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
      '';
    };
  };
  
  # Add NGINX virtual host for Glances
  services.nginx.virtualHosts."glances.${config.networking.hostName}.${config.networking.domain}" = {
    locations."/" = {
      proxyPass = "http://localhost:61208";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
      '';
    };
  };
  
  # Enable CIFS mounts
  cifsShares.enable = true;
  
  # Ensure cifs kernel module is loaded early
  boot.initrd.kernelModules = [ "cifs" ];
  
  # Host-specific networking configuration with hardcoded values
  networking = {
    # Hardcoded hostname as requested
    hostName = "misc";
    domain = "home.arpa";
    
    # Hardcoded network configuration
    interfaces.enp3s0f0 = {
      useDHCP = false;
      ipv4.addresses = [
        { address = "192.168.1.3"; prefixLength = 24; }
      ];
    };
    defaultGateway = "192.168.1.1";
    nameservers = [ "192.168.1.1" ];

    firewall.enable = false;
  };

  # Add misc-specific packages
  environment.systemPackages = with pkgs; [
    cifs-utils
    samba
    certbot
    smartmontools  # Required for Scrutiny's SMART data collection
    glances       # System monitoring tool
    # Add other misc-specific packages here
  ];

  # Enable Glances as a web service
  systemd.services.glances = {
    description = "Glances system monitoring web service";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.glances}/bin/glances -w -t 5 --port 61208 -B 0.0.0.0";
      Restart = "always";
      RestartSec = 3;
      User = "root";  # Running as root to access all system info
    };
  };

  # Console configuration for CLI-only environment
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  # Environment variables that could be referenced by other modules
  environment.variables = {
  };

  # Example usage of environment variables in a systemd service
  systemd.services.example-service = {
    description = "Example service using environment variables";
    enable = false; # Set to true when you actually need this service
    serviceConfig = {
      # Use EnvironmentFile to load all variables from root .env
      EnvironmentFile = [
        "/etc/nixos/.env"
      ];
      # Or inject specific variables directly
      Environment = [
        "HOST_NAME=misc"
        "HOST_IP=192.168.1.3"
      ];
    };
  };
  
  # Example virtual host with ACME/certbot integration
  # Commented out until you have a real domain to use
  /*
  services.nginx.virtualHosts."example.com" = {
    enableACME = true;
    forceSSL = true;
    
    # Basic site configuration
    root = "/var/www/example.com";
    locations = {
      "/" = {
        index = "index.html index.htm";
        tryFiles = "$uri $uri/ =404";
      };
    };
    
    # Include the shared SSL parameters created in the activation script
    extraConfig = ''
      include /etc/nginx/ssl/options-ssl-nginx.conf;
      ssl_dhparam /etc/nginx/ssl/ssl-dhparams.pem;
    '';
  };
  
  /* 
  security.acme = {
    # Default configuration is in modules/nginx.nix
    # Add specific certificates here
    certs = {
      "example.com" = {
        extraDomainNames = [ "www.example.com" ];
        # Email is already defined globally in modules/nginx.nix from MAIN_EMAIL
        # No need to specify email here as it will use the default from nginx.nix
        # No need to specify webroot or credentials - NixOS handles this
        postRun = "systemctl reload nginx.service";
      };
    };
  };
  */
  
  # Make sure the webroot directory exists (this is still useful for future use)
  system.activationScripts.nginxWebroot = ''
    mkdir -p /var/www
    chmod -R 755 /var/www
  '';
}