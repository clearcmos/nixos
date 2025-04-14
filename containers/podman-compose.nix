# NixOS module for managing Podman Compose containers
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.podman-compose;
  
  # Convert filename to service name (remove extension)
  filenameToName = filename:
    let
      basename = builtins.baseNameOf filename;
      name = builtins.head (builtins.split "\\." basename);
    in
      name;
  
  # Define compose files explicitly instead of reading from filesystem
  composeFiles = [
    "glances.yml"
    "scrutiny.yml"
    "radarr.yml"
    "sabnzbd.yml"
    "sonarr.yml"
    "authentik.yml"
  ];
  
  # Create a list of paths to all compose files
  composeFilePaths = map (name: "/etc/nixos/containers/${name}") composeFiles;
  
  # Create a set of compose project names from file names
  composeProjects = map filenameToName composeFiles;
  
  # Function to create a service for a compose file
  createComposeService = file: 
    let
      # Get project name from filename
      projectName = filenameToName file;
      
      # Define directory for volume storage
      volumeDir = "/var/lib/containers/storage/volumes/${projectName}";
    in
    {
      description = "Podman Compose for ${projectName}";
      path = [ pkgs.podman-compose pkgs.podman pkgs.coreutils pkgs.gnused pkgs.bash pkgs.gawk pkgs.gnugrep ];
      
      # Ensure appropriate ordering
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      
      # Handle volumes before starting
      preStart = ''
        # Create project volume directory
        mkdir -p ${volumeDir}
        
        # Create symlink to original .env file instead of copying
        if [ -f /etc/nixos/.env ]; then
          # Remove any existing file or directory first
          rm -f ${volumeDir}/.env
          ln -sf /etc/nixos/.env ${volumeDir}/.env
        fi
        
        # Extract and create volume directories for relative paths
        cd /etc/nixos/containers
        
        # Process volumes that start with ./
        # Specifically look for volume paths in the volumes section
        grep -E '^\s*-\s*\./[^ :]*' "${file}" 2>/dev/null | grep -o '\./[^ :]*' | while read -r vol_path; do
          # Skip .env paths which are not real volumes
          if [ "$vol_path" = "./.env" ]; then
            continue
          fi
          
          # Remove ./ prefix to get the volume name
          vol_name=$(echo "$vol_path" | sed 's|^\./||' | cut -d '/' -f1)
          
          # Create the volume directory
          mkdir -p "${volumeDir}/$vol_name"
          echo "Created volume directory: ${volumeDir}/$vol_name"
        done
      '';
      
      # Main service script
      script = ''
        cd /etc/nixos/containers
        PROJECT_NAME="${projectName}"
        COMPOSE_FILE="${file}"
        
        echo "Managing Podman Compose project: $PROJECT_NAME"
        
        # Create a modified compose file with replaced volume paths
        TMP_COMPOSE=$(mktemp)
        cp "$COMPOSE_FILE" "$TMP_COMPOSE"
        
        # Replace relative volume paths (./path) with absolute paths to our volume dir
        sed -i "s|\\./|${volumeDir}/|g" "$TMP_COMPOSE"
        
        # Also modify env_file paths to point to our volume dir
        sed -i "s|env_file:\\s*\\n\\s*-\\s*/etc/nixos/\\.env|env_file:\\n      - ${volumeDir}/.env|g" "$TMP_COMPOSE"
        
        # Function to run podman-compose with environment variables
        run_compose() {
          # Process the environment file more safely
          if [ -f "/etc/nixos/.env" ]; then
            # Export variables one by one, ignoring problematic lines
            while IFS= read -r line || [ -n "$line" ]; do
              # Skip comments and empty lines
              [[ "$line" =~ ^[[:space:]]*# ]] && continue
              [[ -z "$line" ]] && continue
              
              # Only process proper VAR=VALUE lines
              if [[ "$line" =~ ^[A-Za-z0-9_]+=.* ]]; then
                export "$line"
              fi
            done < "/etc/nixos/.env"
          fi
          
          # Run the podman-compose command with explicit project name
          podman-compose -f "$TMP_COMPOSE" -p "$PROJECT_NAME" "$@"
        }
        
        # Simple approach: always stop and start containers
        echo "Managing containers for $PROJECT_NAME"
        
        # Pull the latest images
        run_compose pull
        
        # Stop any existing containers
        echo "Stopping any existing containers for $PROJECT_NAME"
        run_compose down || true
        
        # Start containers
        echo "Starting containers for $PROJECT_NAME"
        run_compose up -d
        
        # Clean up temporary file
        rm -f "$TMP_COMPOSE"
      '';
      
      # Use oneshot type with RemainAfterExit to manage service state
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };
    
  # Create a service for each compose file
  composeServices = listToAttrs (map
    (file: nameValuePair
      "podman-compose-${filenameToName file}"
      (createComposeService file)
    )
    composeFilePaths
  );
  
in
{
  options.services.podman-compose = {
    enable = mkEnableOption "Enable Podman Compose services";
  };

  config = mkIf cfg.enable {
    # Ensure podman and podman-compose are installed
    environment.systemPackages = with pkgs; [
      podman
      podman-compose
      podman-tui
      
      # Additional dependencies required for our scripts
      gnused
      gawk
      gettext # For envsubst
    ];
    
    # Enable podman socket and service
    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
    
    # Create systemd services for each compose file
    systemd.services = composeServices;
    
    # Create parent directories for container volumes
    systemd.tmpfiles.rules = [
      "d /var/lib/containers 0755 root root - -"
      "d /var/lib/containers/storage 0755 root root - -"
      "d /var/lib/containers/storage/volumes 0755 root root - -"
    ];
  };
}