{ config, lib, pkgs, modulesPath, ... }:

let
  # Helper function to load environment variables from .env file
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

  # Attempt to load the .env file, or use empty set if it doesn't exist
  envFile = "/etc/nixos/.env";
  envExists = builtins.pathExists envFile;
  env = if envExists then loadEnvFile envFile else {};

  # Function to get a value from the env file with a default
  getEnv = name: default: if builtins.hasAttr name env
                         then env.${name}
                         else default;
                         
  # Get username and other environment variables
  username = getEnv "USERNAME" "nixuser";
  githubUsername = getEnv "GITHUB_USER" "nixuser";
  emailAddress = getEnv "GITHUB_EMAIL" "";
  sshKey = getEnv "SSH_AUTHORIZED_KEY" "";
  hashedPassword = getEnv "USER_HASHED_PASSWORD" "";

in
{
  imports = [
    ./containers/glances.nix
    ./containers/scrutiny.nix
    ./stacks/claude.nix
    ./stacks/git.nix
    ./stacks/nginx.nix
    ./aliases.nix
    ./hardware-configuration.nix
  ];
  
  # Share username with other modules
  options.mainUser = with lib; {
    username = mkOption {
      type = types.str;
      default = username;
      description = "Main username for the system, shared with other modules";
    };
  };
  
  config = {
    # Set the main username value
    mainUser.username = username;

    #
    # BOOT CONFIGURATION
    #
    boot = {
    # Use the systemd-boot EFI boot loader
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    # Support for mounting CIFS/SMB and NFS shares
    supportedFilesystems = [ "cifs" "nfs" ];
  };

  #
  # AUDIO CONFIGURATION
  #
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;  # Needed for PipeWire
  
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  #
  # LOCALE CONFIGURATION
  #
  # Set your time zone
  time.timeZone = "America/New_York";
  
  # Select internationalisation properties
  i18n.defaultLocale = "en_US.UTF-8";

  #
  # NETWORKING CONFIGURATION
  #
  networking = {
    # Set your hostname and domain
    hostName = "nix";
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

    firewall.enable = false;
  };

  #
  # PACKAGES CONFIGURATION
  #
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile (alphabetically ordered)
  environment.systemPackages = with pkgs; [
    cacert
    cifs-utils
    compose2nix
    curl
    fzf
    git
    gnupg
    htop
    ipcalc
    jq
    ncdu
    nmap
    nodejs
    pkg-config
    podman
    python3
    rsync
    samba
    sudo
    tldr
    wget
  ];

  # ENVIRONMENT VARIABLES USAGE
  #
  # Example usage of environment variables in a systemd service
  systemd.services.example-service = {
    description = "Example service using environment variables";
    enable = false; # Set to true when you actually need this service
    serviceConfig = {
      # Use EnvironmentFile to load all variables
      EnvironmentFile = [
        "/etc/nixos/.env"
      ];
      # Or inject specific variables directly
      Environment = [
        "API_KEY=${getEnv "API_KEY" "default-placeholder-value"}"
      ];
    };
  };

  #
  # SERVICES CONFIGURATION
  #
  # SSH configuration
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";  # Allow root login with key auth only
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
    # Configure allowed users with IP restrictions
    extraConfig = ''
      # Allow regular user from anywhere
      AllowUsers ${username}
      
      # Allow root only from local network
      Match Address 192.168.1.0/24
          AllowUsers root
    '';
  };
  
  # Create the SSH authorized keys using systemd services
  systemd.services.setup-root-ssh-key = {
    description = "Setup root SSH authorized keys";
    wantedBy = [ "multi-user.target" ];
    script = ''        
      if [ ! -z "${sshKey}" ]; then
        # Setup authorized key for remote login
        echo "${sshKey}" > /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
        chown root:root /root/.ssh/authorized_keys
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.coreutils ];
    preStart = ''
      mkdir -p /root/.ssh
      chmod 700 /root/.ssh
    '';
  };

  systemd.services.setup-user-ssh-key = {
    description = "Setup user SSH authorized keys";
    wantedBy = [ "multi-user.target" ];
    script = ''
      if [ ! -z "${sshKey}" ]; then
        # Setup authorized key for remote login
        echo "${sshKey}" > /home/${username}/.ssh/authorized_keys
        chmod 600 /home/${username}/.ssh/authorized_keys
        chown ${username}:users /home/${username}/.ssh/authorized_keys
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.coreutils ];
    preStart = ''
      mkdir -p /home/${username}/.ssh
      chmod 700 /home/${username}/.ssh
      chown ${username}:users /home/${username}/.ssh
    '';
  };

  # File sharing services
  services.samba = {
    enable = true;
    # Additional Samba configuration would go here
  };

  # Enable nix-ld for better compatibility with non-NixOS binaries
  programs.nix-ld.enable = true;

  # Automatic system updates
  system.autoUpgrade = {
    enable = true;                     # Enable automatic upgrades
    allowReboot = false;               # Set to true if you want automatic reboots
    dates = "04:00";                   # Run at 4 AM
    randomizedDelaySec = "45min";      # Add random delay to prevent everyone updating at once
    persistent = true;                 # Continue interrupted downloads on next boot
    # channel = "https://nixos.org/channels/nixos-23.11"; # Optional: specify channel URL
    # flake = "github:yourusername/your-nixos-config"; # Optional: use flakes instead of channels
  };

  #
  # USERS CONFIGURATION
  #
  # Define user settings
  
  # Define user account with SSH key and password from .env
  users.users.${username} = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ]; # Enable 'sudo' for the user
    # Use the SSH key from .env if provided
    openssh.authorizedKeys.keys = if sshKey != "" then [ sshKey ] else [];
    # Use the hashed password from .env if provided
    hashedPassword = if hashedPassword != "" then hashedPassword else null;
    createHome = true;
    home = "/home/${username}";
  };

  # Allow user passwords to be changed
  users.mutableUsers = true;
  
  # Generate SSH keys with proper usernames and hostnames
  systemd.services.generate-ssh-keys = {
    description = "Generate SSH keys with proper username and hostname";
    wantedBy = [ "multi-user.target" ];
    script = ''
      # For root user
      if [ ! -f "/root/.ssh/id_ed25519" ]; then
        echo "Generating new SSH key for root"
        ssh-keygen -t ed25519 -f "/root/.ssh/id_ed25519" -N "" -C "root@$(hostname)"
        echo "SSH key generated for root"
      else
        echo "SSH key already exists for root"
        # Ensure comment has proper format even for existing keys
        current_key=$(cat "/root/.ssh/id_ed25519.pub")
        # Get hostname once to ensure consistency
        host=$(hostname)
        # Check if key has proper root@hostname format
        if [[ "$current_key" != *"root@$host" ]]; then
          # Extract the key part without the comment
          key_part=$(echo "$current_key" | awk '{print $1 " " $2}')
          # Create new key with proper comment
          echo "$key_part root@$host" > "/root/.ssh/id_ed25519.pub"
          echo "Updated root key comment to root@$host"
        fi
      fi
      
      # For regular user
      if [ ! -f "/home/${username}/.ssh/id_ed25519" ]; then
        echo "Generating new SSH key for ${username}"
        mkdir -p "/home/${username}/.ssh"
        chmod 700 "/home/${username}/.ssh"
        ssh-keygen -t ed25519 -f "/home/${username}/.ssh/id_ed25519" -N "" -C "${username}@$(hostname)"
        echo "SSH key generated for ${username}"
        chown -R ${username}:users "/home/${username}/.ssh"
      else
        echo "SSH key already exists for ${username}"
        # Ensure comment has proper format even for existing keys
        current_key=$(cat "/home/${username}/.ssh/id_ed25519.pub")
        # Get hostname once to ensure consistency
        host=$(hostname)
        # Check if key has proper username@hostname format
        if [[ "$current_key" != *"${username}@$host" ]]; then
          # Extract the key part without the comment
          key_part=$(echo "$current_key" | awk '{print $1 " " $2}')
          # Create new key with proper comment
          echo "$key_part ${username}@$host" > "/home/${username}/.ssh/id_ed25519.pub"
          echo "Updated ${username} key comment to ${username}@$host"
          chown ${username}:users "/home/${username}/.ssh/id_ed25519.pub"
        fi
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.openssh pkgs.coreutils pkgs.gawk pkgs.hostname ];
    preStart = ''
      mkdir -p /root/.ssh
      chmod 700 /root/.ssh
    '';
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  system.stateVersion = "24.11"; # Do NOT change this unless you know what you're doing!
  };
}
