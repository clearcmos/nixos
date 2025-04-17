# Main configuration file for NixOS
# Edit this file for system-wide configuration
{ config, lib, pkgs, modulesPath, ... }:

let
  # Load environment variables from .env file
  loadEnv = path:
    let
      content = builtins.readFile path;
      # Split into lines and filter comments/empty lines
      lines = lib.filter (line:
        line != "" &&
        !(lib.hasPrefix "#" line)
      ) (lib.splitString "\n" content);

      # Split each line into key/value with improved handling for quotes and special chars
      parseLine = line:
        let
          # Use a more robust regex that handles quotes and spaces around equals sign
          match = builtins.match "([^=]+)=([\"']?)([^\"]*)([\"']?)" line;
          key = if match == null then null else lib.elemAt match 0;
          # Extract the value without quotes
          value = if match == null then null else lib.elemAt match 2;
        in if match == null
           then null
           else { name = lib.removeSuffix " " (lib.removePrefix " " key); value = value; };

      # Convert to attribute set, filtering out null values from parsing failures
      parsedLines = map parseLine lines;
      validLines = builtins.filter (x: x != null) parsedLines;
      env = builtins.listToAttrs validLines;
    in env;

  envVars = loadEnv "/etc/nixos/.env";

  # Get values from environment files
  cloudflare_domain = envVars.CLOUDFLARE_DOMAIN;
  system_password = envVars.SYSTEM_PASSWORD;
  ssh_authorized_key = envVars.SSH_AUTHORIZED_KEY;
  main_email = envVars.MAIN_EMAIL;
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
    
    # Explicitly set UIDs for nixbld users with mkForce to override defaults
    nixbld1 = { isSystemUser = true; group = "nixbld"; uid = lib.mkForce 999; };
    nixbld2 = { isSystemUser = true; group = "nixbld"; uid = lib.mkForce 998; };
    nixbld3 = { isSystemUser = true; group = "nixbld"; uid = lib.mkForce 997; };
    nixbld4 = { isSystemUser = true; group = "nixbld"; uid = lib.mkForce 996; };
    nixbld5 = { isSystemUser = true; group = "nixbld"; uid = lib.mkForce 995; };
    nixbld6 = { isSystemUser = true; group = "nixbld"; uid = lib.mkForce 994; };
    nixbld7 = { isSystemUser = true; group = "nixbld"; uid = lib.mkForce 993; };
    nixbld8 = { isSystemUser = true; group = "nixbld"; uid = lib.mkForce 992; };
    nixbld9 = { isSystemUser = true; group = "nixbld"; uid = lib.mkForce 991; };
    nixbld10 = { isSystemUser = true; group = "nixbld"; uid = lib.mkForce 990; };
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

    # Additional SSL settings for better security and compatibility
    sslCiphers = "EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH";
    sslProtocols = "TLSv1.2 TLSv1.3";

    # Virtual hosts configuration
    virtualHosts = {
      "scrutiny.${lib.removeSuffix "." cloudflare_domain}" = {
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          proxyPass = "http://localhost:8080";
          proxyWebsockets = true;
        };
        # Extra config to ensure headers are properly passed
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
        '';
      };

      "glances.${lib.removeSuffix "." cloudflare_domain}" = {
        forceSSL = true;
        enableACME = true;
        locations = {
          "/" = {
            proxyPass = "http://localhost:61208";
            proxyWebsockets = true;
          };
          "/static/" = {
            proxyPass = "http://localhost:61208/static/";
          };
          "/api" = {
            proxyPass = "http://localhost:61208/api";
            proxyWebsockets = true;
          };
        };
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_read_timeout 300s;
          proxy_send_timeout 300s;
        '';
      };
      
      "jellyfin.${lib.removeSuffix "." cloudflare_domain}" = {
        forceSSL = true;
        enableACME = true;
        locations = {
          "/" = {
            # Using domain name approach instead of IP address
            proxyPass = "http://jellyimmich.home.arpa:8096";
            proxyWebsockets = true;
          };
        };
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          
          # Jellyfin-specific settings
          proxy_buffering off;
          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
          
          # Increased timeouts for streaming content
          proxy_read_timeout 600s;
          proxy_send_timeout 600s;
          
          # Allow large uploads
          client_max_body_size 0;
          
          # Disable compression for video content
          proxy_set_header Accept-Encoding "";
        '';
      };

      "photos.${lib.removeSuffix "." cloudflare_domain}" = {
        forceSSL = true;
        enableACME = true;
        locations = {
          "/" = {
            proxyPass = "http://jellyimmich.home.arpa:2283";
            proxyWebsockets = true;
          };
        };
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          
          # Immich-specific settings
          proxy_buffering off;
          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
          
          # Increased timeouts for media content
          proxy_read_timeout 600s;
          proxy_send_timeout 600s;
          
          # Allow large uploads
          client_max_body_size 0;
        '';
      };
    };
  };

  # ACME (Let's Encrypt) configuration
  security.acme = {
    acceptTerms = true;
    defaults.email = main_email;

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
  
  # Enable nix-ld for running non-NixOS executables (needed for VS Code Remote SSH)
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # Common libraries needed for VS Code Remote SSH and other tools
    stdenv.cc.cc.lib
    zlib
    openssl
    curl
    expat
    which
    xz
    icu
    zstd
    libsecret
    # Add more libraries if needed for specific tools
  ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  system.stateVersion = "23.05";
}
