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
      after = [ "network-online.target" "mount-cifs-shares.service" ];
      wants = [ "network-online.target" ];
      requires = [ "mount-cifs-shares.service" ];
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
        
        # Check if project volume directory already contains data (excluding .env symlink)
        if [ -n "$(ls -A "${volumeDir}" 2>/dev/null | grep -v '^\.env$')" ]; then
          echo "Project volume directory ${volumeDir} already contains data. Skipping initialization."
          exit 0
        fi
        
        echo "Project volume directory ${volumeDir} is empty, creating necessary subdirectories..."
        
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
          echo "Created volume directory: ''${volumeDir}/$vol_name"
          
          # Check if the volume directory is empty and needs to be initialized
          if [ -z "$(ls -A "${volumeDir}/$vol_name" 2>/dev/null)" ]; then
            echo "Volume ''${volumeDir}/$vol_name is empty, initializing..."
            
            # No backup restoration, always create empty volume structure
            echo "Creating empty volume structure for $vol_name"
              # For database volumes, let the container initialize them
              if [[ "$vol_name" = "database" && "${projectName}" = "authentik" ]]; then
                # Special case for postgres - leave it empty to allow postgres to initialize
                chmod 700 "${volumeDir}/$vol_name"
                chown 70:0 "${volumeDir}/$vol_name"
              else
                # Default case - just ensure permissions are set
                chmod 755 "${volumeDir}/$vol_name"
              fi
            fi
          fi
        done
        
        # Also check volume names defined in the Docker Compose volumes section
        grep -A20 "^volumes:" "${file}" 2>/dev/null | grep -v "^volumes:" | grep -E "^\s+[a-zA-Z0-9_-]+:" | grep -v "driver:" | grep -o "^\s*[a-zA-Z0-9_-]\+" | while read -r named_volume; do
          # Skip empty lines
          [ -z "$named_volume" ] && continue
          
          # Trim whitespace
          named_volume=$(echo "$named_volume" | xargs)
          
          # Create named volume directory
          if [ ! -z "$named_volume" ]; then
            mkdir -p "${volumeDir}/$named_volume"
            echo "Created named volume directory: ''${volumeDir}/$named_volume"
            
            # Check if the volume directory is empty and needs to be initialized
            if [ -z "$(ls -A "${volumeDir}/$named_volume" 2>/dev/null)" ]; then
              echo "Named volume ''${volumeDir}/$named_volume is empty, initializing..."
              
              # No backup restoration, always create empty volume structure
              echo "Creating empty volume structure for $named_volume"
                # For database volumes, set proper permissions but don't create structure
                if [[ "$named_volume" = "database" && "${projectName}" = "authentik" ]]; then
                  # Special case for postgres - leave it empty to allow postgres to initialize
                  chmod 700 "${volumeDir}/$named_volume"
                  chown 70:0 "${volumeDir}/$named_volume"
                fi
              fi
            fi
          fi
        done
      '';
      
      # Main service script
      script = ''
        cd /etc/nixos/containers
        # Define PROJECT_NAME at the Nix level to avoid undefined variable errors
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
        
        echo "Managing containers for $PROJECT_NAME"
        
        # Check if containers are already running
        RUNNING_CONTAINERS=$(podman ps --format "{{.Names}}" | grep "^$PROJECT_NAME" | wc -l)
        
        if [ "$RUNNING_CONTAINERS" -gt 0 ]; then
          echo "Containers for $PROJECT_NAME are already running. Skipping recreation at boot."
        else
          # Only pull images once a week instead of daily to reduce Docker Hub rate limits
          LAST_PULL_FILE="/var/lib/containers/storage/volumes/${projectName}/.last_pull"
          CURRENT_WEEK=$(date +%Y%U)  # ISO week number format YYYYWW
          
          if [ ! -f "$LAST_PULL_FILE" ] || [ "$(cat $LAST_PULL_FILE 2>/dev/null)" != "$CURRENT_WEEK" ]; then
            # Check if all images already exist locally before pulling
            MISSING_IMAGES=0
            
            # Extract all image names from the compose file
            IMAGES=$(grep -E '^\s+image:' "$COMPOSE_FILE" | awk '{print $2}')
            
            for IMAGE in $IMAGES; do
              # Check if image exists locally
              if ! podman image exists "$IMAGE"; then
                MISSING_IMAGES=1
                break
              fi
            done
            
            if [ "$MISSING_IMAGES" -eq 1 ]; then
              echo "Pulling images for $PROJECT_NAME (missing images or weekly update)"
              run_compose pull
              echo "$CURRENT_WEEK" > "$LAST_PULL_FILE"
            else
              echo "All images already exist locally. Skipping pull."
            fi
          else
            echo "Images were already pulled this week. Skipping."
          fi
          
          # Stop and remove any existing containers with same names
          echo "Stopping and removing any existing containers for $PROJECT_NAME"
          run_compose down -v || true
          
          # Force remove any lingering containers with this project name
          echo "Cleaning up any leftover containers"
          podman ps -a --format "{{.Names}}" | grep "^$PROJECT_NAME""_" | xargs -r podman rm -f || true
          
          # Start containers with replace option
          echo "Starting containers for $PROJECT_NAME"
          run_compose up -d
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