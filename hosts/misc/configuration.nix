# Host-specific configuration for misc
{ config, lib, pkgs, ... }:

{
  # Enable flakes and nix-command
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  imports = [
    ../../modules/claude.nix
    ../../modules/nginx.nix
    ../../modules/cifs-mounts.nix
  ];
  
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
    # Add other misc-specific packages here
  ];

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