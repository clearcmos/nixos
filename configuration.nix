# Main configuration file for NixOS
# Edit this file for system-wide configuration
{ config, lib, pkgs, modulesPath, ... }:

let
  # Get values from environment files
  cloudflare_domain = (builtins.getEnv "CLOUDFLARE_DOMAIN");
  system_password = (builtins.getEnv "SYSTEM_PASSWORD");
  ssh_authorized_key = (builtins.getEnv "SSH_AUTHORIZED_KEY");
in
{
  imports =
    [ # Include the hardware configuration
      ./hardware-configuration.nix
    ];

  # Enable flakes and nix-command
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Boot configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelModules = [ "kvm-intel" "wl" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.broadcom_sta ];

  # Host-specific networking configuration
  networking = {
    hostName = "misc";
    domain = "home.arpa";
    
    # Network configuration
    interfaces.enp3s0f0 = {
      useDHCP = false;
      ipv4.addresses = [
        { address = "192.168.1.3"; prefixLength = 24; }
      ];
    };
    defaultGateway = "192.168.1.1";
    nameservers = [ "192.168.1.1" ];

    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 80 443 ]; # SSH, HTTP, HTTPS
    };
  };

  # Set time zone
  time.timeZone = "America/New_York";

  # System packages
  environment.systemPackages = with pkgs; [
    # Basic utilities
    vim
    wget
    curl
    git
    htop
    cifs-utils
    samba
    smartmontools

    # Additional tools
    tmux
    tree
    unzip
    
    # Required packages
    scrutiny
    glances
  ];

  # Console configuration
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  # Environment variables
  environment.variables = {
    EDITOR = "vim";
  };

  # Only allow root user with password from .env
  users.mutableUsers = false;
  
  # Set up users
  users.users = {
    root = {
      password = system_password; # NixOS will hash this
      openssh.authorizedKeys.keys = [ ssh_authorized_key ];
      isSystemUser = true;
      home = "/root";
      group = "root"; # Set the group as required
    };
    
    # ACME needs a user for certificate operations
    acme = {
      isSystemUser = true;
      group = "acme";
      home = "/var/lib/acme";
    };
    
    # Nginx needs a user
    nginx = {
      isSystemUser = true;
      group = "nginx";
      home = "/var/lib/nginx";
    };
    
    # Add NixOS build users
    nixbld1 = { isSystemUser = true; group = "nixbld"; };
    nixbld2 = { isSystemUser = true; group = "nixbld"; };
    nixbld3 = { isSystemUser = true; group = "nixbld"; };
    nixbld4 = { isSystemUser = true; group = "nixbld"; };
    nixbld5 = { isSystemUser = true; group = "nixbld"; };
    nixbld6 = { isSystemUser = true; group = "nixbld"; };
    nixbld7 = { isSystemUser = true; group = "nixbld"; };
    nixbld8 = { isSystemUser = true; group = "nixbld"; };
    nixbld9 = { isSystemUser = true; group = "nixbld"; };
    nixbld10 = { isSystemUser = true; group = "nixbld"; };
  };
  
  # Define the required groups
  users.groups = {
    root = {};
    nginx = {};
    acme = {};
    nixbld = {};
  };
  
  # NixOS build users
  nix.settings.trusted-users = [ "root" ];
  nix.settings.allowed-users = [ "@wheel" "root" ];

  # Enable SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password"; # Allow only key-based login for root
      PasswordAuthentication = false;
    };
  };

  # Nginx configuration
  services.nginx = {
    enable = true;
    
    # Recommended settings
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    
    # Virtual hosts configuration
    virtualHosts = {
      "scrutiny.${cloudflare_domain}" = {
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          proxyPass = "http://localhost:8080";
          proxyWebsockets = true;
        };
      };
      
      "glances.${cloudflare_domain}" = {
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          proxyPass = "http://localhost:61208";
          proxyWebsockets = true;
        };
      };
    };
  };

  # ACME (Let's Encrypt) configuration
  security.acme = {
    acceptTerms = true;
    defaults.email = "admin@${cloudflare_domain}";
    
    # Add required user for ACME
    defaults.group = "nginx";
    defaults.webroot = "/var/lib/acme/acme-challenge";
  };
  
  # Scrutiny service
  services.scrutiny = {
    enable = true;
    settings = {
      web.listen = {
        port = 8080;
        host = "127.0.0.1"; # Only listen on localhost, nginx handles external access
      };
    };
  };
  
  # Glances service
  services.glances = {
    enable = true;
    port = 61208;
    extraArgs = [
      "--webserver"
      "--bind=127.0.0.1"
    ];
  };

  # System activation scripts
  system.activationScripts.protectEnvFile = ''
    # Protect env file with restricted permissions
    chmod 600 /etc/nixos/.env
  '';

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  system.stateVersion = "23.05";
}