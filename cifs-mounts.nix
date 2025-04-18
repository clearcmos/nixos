# CIFS Mounts module for NixOS
{ config, lib, pkgs, ... }:

let
  # Helper function to load environment variables from .env file
  # This reuses the same pattern as in your other modules
  loadEnv = path:
    let
      content = builtins.readFile path;
      lines = lib.filter (line:
        line != "" &&
        !(lib.hasPrefix "#" line)
      ) (lib.splitString "\n" content);

      parseLine = line:
        let
          match = builtins.match "([^=]+)=([\"']?)([^\"]*)([\"']?)" line;
          key = if match == null then null else lib.elemAt match 0;
          value = if match == null then null else lib.elemAt match 2;
        in if match == null
           then null
           else { name = lib.removeSuffix " " (lib.removePrefix " " key); value = value; };

      parsedLines = map parseLine lines;
      validLines = builtins.filter (x: x != null) parsedLines;
      env = builtins.listToAttrs validLines;
    in env;

  # Load environment variables from .env file
  envVars = loadEnv "/etc/nixos/.secrets/.env";

  # Extract CIFS configuration values from environment variables
  system_username = "root"; # Changed from envVars.SYSTEM_USERNAME to use root instead
  
  # Host information
  cifsHost1 = envVars.CIFS_HOST_1 or "msi.home.arpa";
  cifsHost2 = envVars.CIFS_HOST_2 or "syno.home.arpa";
  
  # Share names
  cifsHost1Share1 = envVars.CIFS_HOST_1_SHARE_1 or "";
  cifsHost1Share2 = envVars.CIFS_HOST_1_SHARE_2 or "";
  cifsHost2Share1 = envVars.CIFS_HOST_2_SHARE_1 or "";
  cifsHost2Share2 = envVars.CIFS_HOST_2_SHARE_2 or "";
  
  # Authentication credentials
  cifsHost1User = envVars.CIFS_HOST_1_USER or "";
  cifsHost1Pass = envVars.CIFS_HOST_1_PASS or "";
  cifsHost2User = envVars.CIFS_HOST_2_USER or "";
  cifsHost2Pass = envVars.CIFS_HOST_2_PASS or "";

in {
  # Define module options
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

  # Module implementation
  config = lib.mkIf config.cifsShares.enable {
    # Ensure CIFS tools are installed
    environment.systemPackages = with pkgs; [
      cifs-utils
      samba
      inetutils # For ping
    ];

    # Add cifs to kernel modules to ensure it's loaded
    boot.kernelModules = [ "cifs" ];

    # Create secure credential files during system activation
    system.activationScripts.cifsCredentials = ''
      # Create credential files securely
      mkdir -p /etc
      
      echo "Creating CIFS credential files..."
      
      # Create host1 credentials file
      cat > /etc/.host1-cifs << EOF
username=${cifsHost1User}
password=${cifsHost1Pass}
EOF
      chmod 600 /etc/.host1-cifs

      # Create host2 credentials file
      cat > /etc/.host2-cifs << EOF
username=${cifsHost2User}
password=${cifsHost2Pass}
EOF
      chmod 600 /etc/.host2-cifs
      
      echo "CIFS credential files created successfully"
    '';

    # Create mount points if enabled
    system.activationScripts.cifsMountPoints = lib.mkIf config.cifsShares.createMountPoints ''
      # Create mount points
      mkdir -p /mnt/${cifsHost1Share1}
      mkdir -p /mnt/${cifsHost1Share2}
      mkdir -p /mnt/${cifsHost2Share1}
      mkdir -p /mnt/${cifsHost2Share2}
      
      # Set appropriate permissions
      chown ${system_username}:users /mnt/${cifsHost1Share1}
      chown ${system_username}:users /mnt/${cifsHost1Share2}
      chown ${system_username}:users /mnt/${cifsHost2Share1}
      chown ${system_username}:users /mnt/${cifsHost2Share2}
    '';

    # Create a systemd service for mounting CIFS shares
    systemd.services.mount-cifs-shares = {
      description = "Mount CIFS Shares";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      
      path = with pkgs; [ 
        coreutils 
        gnugrep 
        gnused 
        cifs-utils 
        util-linux 
        inetutils # For ping
      ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeScript "mount-cifs-shares" ''
          #!/bin/sh
          
          # Check if hosts are reachable before attempting to mount
          echo "Checking if CIFS hosts are reachable..."
          
          HOST1="${cifsHost1}"
          HOST2="${cifsHost2}"
          
          # Function to check if a host is up using ping
          check_host() {
            local host=$1
            local attempts=5
            local counter=0
            
            echo "Checking if $host is reachable..."
            
            while [ $counter -lt $attempts ]; do
              if ping -c 1 -W 2 $host >/dev/null 2>&1; then
                echo "$host is reachable."
                return 0
              fi
              
              counter=$((counter + 1))
              echo "Attempt $counter/$attempts: $host is not reachable, retrying in 5 seconds..."
              sleep 5
            done
            
            echo "$host is not reachable after $attempts attempts."
            return 1
          }
          
          # Check if we should skip mounting because shares are already mounted
          if ${if config.cifsShares.skipIfMounted then "true" else "false"}; then
            # Check if all shares are mounted
            SHARE1_MOUNTED=$(mount | grep -q "/mnt/${cifsHost1Share1}" && echo "yes" || echo "no")
            SHARE2_MOUNTED=$(mount | grep -q "/mnt/${cifsHost1Share2}" && echo "yes" || echo "no")
            SHARE3_MOUNTED=$(mount | grep -q "/mnt/${cifsHost2Share1}" && echo "yes" || echo "no")
            SHARE4_MOUNTED=$(mount | grep -q "/mnt/${cifsHost2Share2}" && echo "yes" || echo "no")
            
            # If all are mounted, skip the remounting process
            if [ "$SHARE1_MOUNTED" = "yes" ] && [ "$SHARE2_MOUNTED" = "yes" ] && [ "$SHARE3_MOUNTED" = "yes" ] && [ "$SHARE4_MOUNTED" = "yes" ]; then
              echo "All CIFS shares are already mounted. Skipping remount."
              exit 0
            fi
            
            echo "Some shares are not mounted. Will mount all for consistency."
          fi
          
          # Unmount existing mounts first to ensure clean state
          echo "Unmounting any existing CIFS shares..."
          umount /mnt/${cifsHost1Share1} 2>/dev/null || true
          umount /mnt/${cifsHost1Share2} 2>/dev/null || true
          umount /mnt/${cifsHost2Share1} 2>/dev/null || true
          umount /mnt/${cifsHost2Share2} 2>/dev/null || true
          
          # Ensure the cifs kernel module is loaded
          modprobe cifs
          
          # Mount options with credentials files
          HOST1_OPTS="credentials=/etc/.host1-cifs,uid=${system_username},gid=users,vers=2.1,file_mode=0755,dir_mode=0755,soft,nounix,serverino,mapposix"
          HOST2_OPTS="credentials=/etc/.host2-cifs,uid=${system_username},gid=users,vers=2.1,file_mode=0755,dir_mode=0755,soft,nounix,serverino,mapposix"
          
          # Mount shares for host 1 if it's reachable
          if check_host "$HOST1"; then
            echo "Mounting //$HOST1/${cifsHost1Share1} to /mnt/${cifsHost1Share1}"
            mount -t cifs -o "$HOST1_OPTS" "//$HOST1/${cifsHost1Share1}" /mnt/${cifsHost1Share1} || echo "Failed to mount /mnt/${cifsHost1Share1}"
            
            echo "Mounting //$HOST1/${cifsHost1Share2} to /mnt/${cifsHost1Share2}"
            mount -t cifs -o "$HOST1_OPTS" "//$HOST1/${cifsHost1Share2}" /mnt/${cifsHost1Share2} || echo "Failed to mount /mnt/${cifsHost1Share2}"
          else
            echo "Host $HOST1 is not reachable. Skipping its shares."
          fi
          
          # Mount shares for host 2 if it's reachable
          if check_host "$HOST2"; then
            echo "Mounting //$HOST2/${cifsHost2Share1} to /mnt/${cifsHost2Share1}"
            mount -t cifs -o "$HOST2_OPTS" "//$HOST2/${cifsHost2Share1}" /mnt/${cifsHost2Share1} || echo "Failed to mount /mnt/${cifsHost2Share1}"
            
            echo "Mounting //$HOST2/${cifsHost2Share2} to /mnt/${cifsHost2Share2}"
            mount -t cifs -o "$HOST2_OPTS" "//$HOST2/${cifsHost2Share2}" /mnt/${cifsHost2Share2} || echo "Failed to mount /mnt/${cifsHost2Share2}"
          else
            echo "Host $HOST2 is not reachable. Skipping its shares."
          fi
          
          # List mounted shares
          echo "Mounted CIFS shares:"
          mount | grep cifs || echo "No CIFS shares are currently mounted"
        '';
      };
    };
  };
}