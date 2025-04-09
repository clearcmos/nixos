{ config, pkgs, lib, ... }:

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
  
  githubUsername = getEnv "GITHUB_USER" "nixuser";
  systemUsername = getEnv "USERNAME" "nixuser";
  emailAddress = getEnv "GITHUB_EMAIL" "";
in {
  systemd.services.git-setup = {
    description = "Configure Git credentials for NixOS config";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    path = [ pkgs.git pkgs.openssh pkgs.coreutils ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "${pkgs.bash}/bin/bash -c '[ -d /etc/gitconfig ] && ${pkgs.coreutils}/bin/rm -rf /etc/gitconfig || true'";
      ExecStart = pkgs.writeShellScript "git-ssh-setup" ''
        # Create a log file for debugging
        LOG_FILE="/tmp/git-ssh-setup.log"
        exec > >(tee -a "$LOG_FILE") 2>&1
        
        echo "Starting git-ssh-setup script at $(date)"
        
        # Configure git user
        ${pkgs.git}/bin/git config --file /etc/gitconfig user.email "${emailAddress}"
        ${pkgs.git}/bin/git config --file /etc/gitconfig user.name "${githubUsername}"
        
        # Configure SSH to use keys for GitHub
        SSH_DIR_ROOT="/root/.ssh"
        SSH_DIR_USER="/home/${systemUsername}/.ssh"
        
        echo "Creating SSH directories at $SSH_DIR_ROOT and $SSH_DIR_USER if needed"
        mkdir -p "$SSH_DIR_ROOT" "$SSH_DIR_USER"
        chmod 700 "$SSH_DIR_ROOT" "$SSH_DIR_USER"
        
        # Configure SSH to use these keys for GitHub
        for DIR in "$SSH_DIR_ROOT" "$SSH_DIR_USER"; do
          echo "Configuring SSH config in $DIR"
          cat > "$DIR/config" <<EOF
Host github.com
  IdentityFile $DIR/id_ed25519
  User git
EOF
          chmod 600 "$DIR/config"
        done
        
        # Set ownership for user directory
        chown -R ${systemUsername}:users "$SSH_DIR_USER"
        
        # Display public keys for easy addition to GitHub
        echo ""
        echo "================================================================"
        echo "ROOT PUBLIC KEY (add to GitHub if needed):"
        echo "================================================================"
        cat "$SSH_DIR_ROOT/id_ed25519.pub"
        echo ""
        echo "================================================================"
        echo "USER PUBLIC KEY (add to GitHub if needed):"
        echo "================================================================"
        cat "$SSH_DIR_USER/id_ed25519.pub"
        echo ""
        echo "================================================================"
        echo "SSH keys have been set up. Add the above public keys to your GitHub account."
        echo "For detailed logs, check: $LOG_FILE"
      '';
    };
  };

  # Create a convenient script to display the public keys
  environment.systemPackages = with pkgs; [ 
    git
    openssh
    (pkgs.writeScriptBin "show-github-keys" ''
      #!${pkgs.bash}/bin/bash
      echo "ROOT PUBLIC KEY:"
      cat /root/.ssh/id_ed25519.pub
      echo ""
      echo "USER PUBLIC KEY:"
      cat /home/${systemUsername}/.ssh/id_ed25519.pub
    '')
  ];
}
