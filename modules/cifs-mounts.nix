# CIFS Mounts module for NixOS
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

  # Use absolute path to access .env file
  envFile = /etc/nixos/.env;
  envExists = builtins.pathExists envFile;
  envFileStr = builtins.toString envFile;
  
  # Parse env vars from .env file
  env = if envExists 
        then loadEnvFile envFile 
        else {};

  # env contains the loaded environment variables

  # Function to get a value from the env file with a default
  getEnv = name: default: 
    if builtins.hasAttr name env && env.${name} != ""
    then env.${name}
    else default;

  # Special function for password variables to avoid exposing passwords in logs
  getEnvPass = name: default:
    if builtins.hasAttr name env && env.${name} != ""
    then env.${name}
    else default;

  # Import user module to get username
  username = config.mainUser.username;

  # Get CIFS hosts information
  cifsHost1 = getEnv "CIFS_HOST_1" "msi.home.arpa";
  cifsHost2 = getEnv "CIFS_HOST_2" "syno.home.arpa";
  
  # Get CIFS shares information
  cifsHost1Share1 = getEnv "CIFS_HOST_1_SHARE_1" "";
  cifsHost1Share2 = getEnv "CIFS_HOST_1_SHARE_2" "";
  cifsHost2Share1 = getEnv "CIFS_HOST_2_SHARE_1" "";
  cifsHost2Share2 = getEnv "CIFS_HOST_2_SHARE_2" "";

  # Get CIFS credentials from the .env file
  cifsHost1User = getEnv "CIFS_HOST_1_USER" "";
  cifsHost1Pass = getEnvPass "CIFS_HOST_1_PASS" "";
  cifsHost2User = getEnv "CIFS_HOST_2_USER" "";
  cifsHost2Pass = getEnvPass "CIFS_HOST_2_PASS" "";

in {
  # Define options for enabling/disabling CIFS mounts
  options.cifsShares = with lib; {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to enable CIFS shares";
    };
    
    createMountPoints = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to automatically create mount points";
    };
    
    skipIfMounted = mkOption {
      type = types.bool;
      default = true;
      description = "Skip mounting if shares are already mounted";
    };
  };

  config = lib.mkIf config.cifsShares.enable {
    # Ensure CIFS tools are installed
    environment.systemPackages = with pkgs; [
      cifs-utils
      samba
    ];

    # Add cifs to kernel modules to ensure it's loaded
    boot.kernelModules = [ "cifs" ];

    # Create secure credential files during system activation
    system.activationScripts.cifsCredentials = ''
      # Create credential files securely
      mkdir -p /etc
      
      echo "Creating CIFS credential files..."
      
      # Read passwords directly from the .env file
      ENV_FILE="/etc/nixos/.env"
      echo "Reading credentials from $ENV_FILE"
      
      if [ -f "$ENV_FILE" ]; then
        MSI_USER=$(grep "CIFS_HOST_1_USER" "$ENV_FILE" | cut -d= -f2)
        MSI_PASS=$(grep "CIFS_HOST_1_PASS" "$ENV_FILE" | cut -d= -f2)
        SYNO_USER=$(grep "CIFS_HOST_2_USER" "$ENV_FILE" | cut -d= -f2)
        SYNO_PASS=$(grep "CIFS_HOST_2_PASS" "$ENV_FILE" | cut -d= -f2)
        
        # Create credential files with the values read from .env
        cat > /etc/.msi << EOF
username=$MSI_USER
password=$MSI_PASS
EOF
        chmod 600 /etc/.msi

        cat > /etc/.syno << EOF
username=$SYNO_USER
password=$SYNO_PASS
EOF
        chmod 600 /etc/.syno
        
        echo "CIFS credential files created successfully"
      else
        echo "ERROR: Environment file $ENV_FILE not found!"
        echo "CIFS mounts will likely fail. Please create the .env file with proper credentials."
      fi
    '';

    # Create mount points if enabled
    system.activationScripts.cifsMountPoints = lib.mkIf config.cifsShares.createMountPoints ''
      # Create mount points
      mkdir -p /mnt/bedro
      mkdir -p /mnt/d
      mkdir -p /mnt/syno
      mkdir -p /mnt/syno-backups
      
      # Set appropriate permissions
      chown ${username}:users /mnt/bedro
      chown ${username}:users /mnt/d
      chown ${username}:users /mnt/syno
      chown ${username}:users /mnt/syno-backups
    '';

    # Create a systemd service for mounting CIFS shares
    systemd.services.mount-cifs-shares = {
      description = "Mount CIFS Shares";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      
      path = [ pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.cifs-utils pkgs.util-linux ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeScript "mount-cifs-shares" ''
          #!/bin/sh
          
          # Check if we should skip mounting because shares are already mounted
          if ${if config.cifsShares.skipIfMounted then "true" else "false"}; then
            # Check if all shares are mounted
            BEDRO_MOUNTED=$(mount | grep -q "/mnt/bedro" && echo "yes" || echo "no")
            D_MOUNTED=$(mount | grep -q "/mnt/d" && echo "yes" || echo "no")
            SYNO_MOUNTED=$(mount | grep -q "/mnt/syno" && echo "yes" || echo "no")
            SYNO_BACKUPS_MOUNTED=$(mount | grep -q "/mnt/syno-backups" && echo "yes" || echo "no")
            
            # If all are mounted, skip the remounting process
            if [ "$BEDRO_MOUNTED" = "yes" ] && [ "$D_MOUNTED" = "yes" ] && [ "$SYNO_MOUNTED" = "yes" ] && [ "$SYNO_BACKUPS_MOUNTED" = "yes" ]; then
              echo "All CIFS shares are already mounted. Skipping remount."
              exit 0
            fi
            
            echo "Some shares are not mounted. Will mount all for consistency."
          fi
          
          # Unmount existing mounts first
          echo "Unmounting any existing CIFS shares..."
          umount /mnt/bedro 2>/dev/null || true
          umount /mnt/d 2>/dev/null || true
          umount /mnt/syno 2>/dev/null || true
          umount /mnt/syno-backups 2>/dev/null || true
          
          # Mount CIFS shares using credentials and env vars
          echo "Mounting CIFS shares..."
          
          ENV_FILE="/etc/nixos/.env"
          
          if [ -f "$ENV_FILE" ]; then
            # Extract data from .env file
            MSI_HOST=$(grep "CIFS_HOST_1" "$ENV_FILE" | head -1 | cut -d= -f2)
            MSI_SHARE1=$(grep "CIFS_HOST_1_SHARE_1" "$ENV_FILE" | cut -d= -f2)
            MSI_SHARE2=$(grep "CIFS_HOST_1_SHARE_2" "$ENV_FILE" | cut -d= -f2)
            
            SYNO_HOST=$(grep "CIFS_HOST_2" "$ENV_FILE" | head -1 | cut -d= -f2)
            SYNO_SHARE1=$(grep "CIFS_HOST_2_SHARE_1" "$ENV_FILE" | cut -d= -f2)
            SYNO_SHARE2=$(grep "CIFS_HOST_2_SHARE_2" "$ENV_FILE" | cut -d= -f2)
            
            # Mount options with credentials files
            MSI_OPTS="credentials=/etc/.msi,uid=${username},gid=users,vers=2.1,file_mode=0755,dir_mode=0755,soft,nounix,serverino,mapposix"
            SYNO_OPTS="credentials=/etc/.syno,uid=${username},gid=users,vers=2.1,file_mode=0755,dir_mode=0755,soft,nounix,serverino,mapposix"
            
            # Ensure the cifs kernel module is loaded
            modprobe cifs
            
            # Mount the shares
            echo "Mounting //$MSI_HOST/$MSI_SHARE1 to /mnt/bedro"
            mount -t cifs -o "$MSI_OPTS" "//$MSI_HOST/$MSI_SHARE1" /mnt/bedro || echo "Failed to mount /mnt/bedro"
            
            echo "Mounting //$MSI_HOST/$MSI_SHARE2 to /mnt/d"
            mount -t cifs -o "$MSI_OPTS" "//$MSI_HOST/$MSI_SHARE2" /mnt/d || echo "Failed to mount /mnt/d"
            
            echo "Mounting //$SYNO_HOST/$SYNO_SHARE1 to /mnt/syno"
            mount -t cifs -o "$SYNO_OPTS" "//$SYNO_HOST/$SYNO_SHARE1" /mnt/syno || echo "Failed to mount /mnt/syno"
            
            echo "Mounting //$SYNO_HOST/$SYNO_SHARE2 to /mnt/syno-backups"
            mount -t cifs -o "$SYNO_OPTS" "//$SYNO_HOST/$SYNO_SHARE2" /mnt/syno-backups || echo "Failed to mount /mnt/syno-backups"
            
            # List mounted shares
            echo "Mounted CIFS shares:"
            mount | grep cifs || echo "No CIFS shares are currently mounted"
          else
            echo "ERROR: Environment file $ENV_FILE not found. Cannot mount CIFS shares."
          fi
        '';
      };
    };
  };
}