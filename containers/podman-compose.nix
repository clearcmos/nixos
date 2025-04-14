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
          
          # Run the podman-compose command
          podman-compose -f "$TMP_COMPOSE" "$@"
        }
        
        # Get list of containers in this project
        containers=$(run_compose ps -q 2>/dev/null || echo "")
        
        if [ -z "$containers" ]; then
          echo "No existing containers for $PROJECT_NAME, starting with latest images"
          run_compose pull
          run_compose up -d
        else
          echo "Checking for image updates for $PROJECT_NAME"
          
          # Pull the latest images
          run_compose pull
          
          # Check if any images were updated
          needs_restart=false
          
          # Parse the compose file to get image names
          images=$(grep -E '^\s+image:' "$TMP_COMPOSE" | awk '{print $2}' | sort -u)
          
          for image in $images; do
            # Process the environment file more safely (for image name resolution)
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
            
            # Try to resolve the image name with env vars
            resolved_image=$(echo "$image" | envsubst 2>/dev/null || echo "$image")
            
            # Check if image was updated
            pull_output=$(podman pull "$resolved_image" 2>&1)
            if echo "$pull_output" | grep -q "newer image"; then
              echo "New version of $resolved_image available, will restart containers"
              needs_restart=true
              break
            fi
          done
          
          if $needs_restart; then
            echo "Restarting containers for $PROJECT_NAME due to image updates"
            run_compose down
            run_compose up -d
          else
            # Ensure containers are running
            running_count=$(run_compose ps | grep -c "Up" || echo "0")
            expected_count=$(grep -c "^\s\+image:" "$TMP_COMPOSE" || echo "0")
            
            # Make sure the count variables are integers
            running_count=${running_count:-0}
            expected_count=${expected_count:-0}
            
            echo "Running containers: $running_count, Expected: $expected_count"
            
            # Always start containers if they're not running
            if [ "$running_count" -lt "$expected_count" ]; then
              echo "Some containers are not running, starting all containers"
              run_compose up -d
            else
              echo "Restarting containers for $PROJECT_NAME"
              run_compose down
              run_compose up -d
            fi
          fi
        fi
        
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