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

  # Use absolute path to reference the env file
  envFile = /etc/nixos/common/.env;
  envExists = builtins.pathExists envFile;
  env = if envExists then loadEnvFile envFile else {};

  # Function to get a value from the env file with a default
  getEnv = name: default: if builtins.hasAttr name env
                         then env.${name}
                         else default;

  # Import user module to get username
  username = config.mainUser.username;

  # Get CIFS hosts information
  cifsHost1 = getEnv "CIFS_HOST_1" "msi.home.arpa";
  cifsHost2 = getEnv "CIFS_HOST_2" "syno.home.arpa";
  
  # Get CIFS shares information
  cifsHost1Share1 = getEnv "CIFS_HOST_1_SHARE_1" "Users/bedro";
  cifsHost1Share2 = getEnv "CIFS_HOST_1_SHARE_2" "d";
  cifsHost2Share1 = getEnv "CIFS_HOST_2_SHARE_1" "syno";
  cifsHost2Share2 = getEnv "CIFS_HOST_2_SHARE_2" "syno-backups";

  # Get CIFS credentials from the .env file
  cifsHost1User = getEnv "CIFS_HOST_1_USER" "bedro";
  cifsHost1Pass = getEnv "CIFS_HOST_1_PASS" "";
  cifsHost2User = getEnv "CIFS_HOST_2_USER" "nicholas";
  cifsHost2Pass = getEnv "CIFS_HOST_2_PASS" "";

  # Create credential file content
  host1CredentialsContent = ''
    username=${cifsHost1User}
    password=${cifsHost1Pass}
  '';
  
  host2CredentialsContent = ''
    username=${cifsHost2User}
    password=${cifsHost2Pass}
  '';

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
  };

  config = lib.mkIf config.cifsShares.enable {
    # Ensure CIFS tools are installed
    environment.systemPackages = with pkgs; [
      cifs-utils
      samba
    ];

    # Create secure credential files during system activation
    system.activationScripts.cifsCredentials = ''
      # Create credential files securely
      mkdir -p /etc
      echo "${host1CredentialsContent}" > /etc/.msi
      chmod 600 /etc/.msi
      echo "${host2CredentialsContent}" > /etc/.syno
      chmod 600 /etc/.syno
      
      # Debug: echo credential information to journalctl for troubleshooting
      echo "CIFS credential files created:"
      echo "Host 1 (MSI) username: ${cifsHost1User}"
      echo "Host 1 (MSI) password value: ${cifsHost1Pass}"
      echo "Host 2 (Synology) username: ${cifsHost2User}" 
      echo "Host 2 (Synology) password value: ${cifsHost2Pass}"
      
      # Show actual credential file contents
      echo "MSI credentials file content:"
      cat /etc/.msi
      echo "Synology credentials file content:"
      cat /etc/.syno
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

    # Configure the filesystems
    fileSystems = {
      "/mnt/bedro" = {
        device = "//${cifsHost1}/${cifsHost1Share1}";
        fsType = "cifs";
        options = [
          "credentials=/etc/.msi"
          "rw"
          "file_mode=0777"
          "dir_mode=0777"
          "x-gvfs-show"
          "uid=${username}"
          "gid=users"
        ];
      };
      
      "/mnt/d" = {
        device = "//${cifsHost1}/${cifsHost1Share2}";
        fsType = "cifs";
        options = [
          "credentials=/etc/.msi"
          "rw"
          "file_mode=0777"
          "dir_mode=0777"
          "x-gvfs-show"
          "uid=${username}"
          "gid=users"
        ];
      };
      
      "/mnt/syno" = {
        device = "//${cifsHost2}/${cifsHost2Share1}";
        fsType = "cifs";
        options = [
          "credentials=/etc/.syno"
          "x-gvfs-show"
          "uid=${username}"
          "gid=users"
          "vers=3.0"
          "sec=ntlmssp"
        ];
      };
      
      "/mnt/syno-backups" = {
        device = "//${cifsHost2}/${cifsHost2Share2}";
        fsType = "cifs";
        options = [
          "credentials=/etc/.syno"
          "x-gvfs-show"
          "uid=${username}"
          "gid=users"
          "vers=3.0"
          "sec=ntlmssp"
        ];
      };
    };
  };
}