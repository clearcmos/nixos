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
      # Include nginx configuration
      ./nginx.nix
      # Include packages configuration
      ./packages.nix
      # Include CIFS mounts configuration
      ./cifs-mounts.nix
      # Include custom functions
      ./functions.nix
      # Include site-specific configurations
      ./sites/scrutiny.nix
      ./sites/glances.nix
      ./sites/jellyfin.nix
      ./sites/photos.nix
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
      allowedTCPPorts = [ 22 139 445 ]; # SSH and Samba ports
      allowedUDPPorts = [ 137 138 ]; # Samba ports
    };
  };

  # Set time zone
  time.timeZone = "America/New_York";

  # Console configuration
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  # Only allow root user with password from .env
  users.mutableUsers = false;

  # Set up users (ACME and Nginx users moved to nginx.nix)
  users.users = {
    root = {
      password = system_password; # NixOS will hash this
      openssh.authorizedKeys.keys = [ ssh_authorized_key ];
      isSystemUser = true;
      home = "/root";
      group = "root"; # Set the group as required
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

  # Define the required groups (nginx and acme moved to nginx.nix)
  users.groups = {
    root = {};
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

  # System activation scripts (ACME debug moved to nginx.nix)
  system.activationScripts = {
    protectEnvFile = ''
      # Protect env file with restricted permissions
      chmod 600 /etc/nixos/.env
    '';
    
    # Set the Samba password for root user using the password from .env
    setupSambaPassword = ''
      # Only run if Samba is enabled
      if [ -d /var/lib/samba ]; then
        echo "Setting up Samba password for root user..."
        # Extract password from .env file
        ROOT_PASSWORD=$(grep "SYSTEM_PASSWORD" /etc/nixos/.env | cut -d= -f2)
        
        # Use full path to smbpasswd to ensure it's found
        SMBPASSWD="${pkgs.samba}/bin/smbpasswd"
        
        # Create smbpasswd entry for root
        (echo "$ROOT_PASSWORD"; echo "$ROOT_PASSWORD") | $SMBPASSWD -s -a root
        echo "Samba password for root user has been set"
      fi
    '';
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  
  # Enable nix-ld for running non-NixOS executables (needed for VS Code Remote SSH)
  programs.nix-ld.enable = true;
  
  # Samba configuration for root filesystem access
  services.samba = {
    enable = true;
    securityType = "user";
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "NixOS Server";
        "server role" = "standalone server";
        "log file" = "/var/log/samba/smbd.log";
        "max log size" = "50";
        "hosts allow" = "192.168.1.2 127.0.0.1";
        "hosts deny" = "all";
        "guest account" = "nobody";
        "map to guest" = "bad user";
        # Override the default "invalid users" setting that blocks root
        "invalid users" = [ ];
      };
      root = {
        "path" = "/";
        "browseable" = "yes";
        "writable" = "yes";
        "valid users" = "root";
        "public" = "no";
        "create mask" = "0755";
        "directory mask" = "0755";
        "force user" = "root";
        "force group" = "root";
      };
    };
  };
  
  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  system.stateVersion = "23.05";
}
