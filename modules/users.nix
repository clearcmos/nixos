# User configuration module for all hosts
{ config, lib, pkgs, ... }:

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
  hashedPassword = getEnv "SYSTEM_PASSWORD" "";

in {
  # Define options for mainUser
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
    
    # SSH configuration for specific users
    services.openssh.extraConfig = ''
      # Allow regular user from anywhere
      AllowUsers ${username}
      
      # Allow root only from local network
      Match Address 192.168.1.0/24
          AllowUsers root
    '';

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
  };
}