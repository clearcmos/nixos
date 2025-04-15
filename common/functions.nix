{
  # Define shell functions for bash
  programs.bash.interactiveShellInit = ''
    pman() {
      # Get sorted list of container names
      containers=$(podman ps --format "{{.Names}}" | sort)
      
      # Find the maximum container name length for formatting
      max_name=$(echo "$containers" | awk '{ if (length > max) max = length } END { print max }')
      
      # Print header with appropriate spacing
      printf "%-''${max_name}s  %s\n" "Container" "URL"
      printf "%-''${max_name}s  %s\n" "$(printf '%0.s-' $(seq 1 $max_name))" "-------------------"
      
      # Get local IP address
      ip=$(ip route get 1.1.1.1 | awk '{print $7; exit}')
      
      # Track used ports
      declare -A used_ports
      
      # Process each container
      for container in $containers; do
        # Get container ID
        container_id=$(podman inspect --format '{{.Id}}' $container)
        
        # Check if container uses host network mode
        network_mode=$(podman inspect --format '{{.HostConfig.NetworkMode}}' $container)
        
        if [ "$network_mode" == "host" ]; then
          # For host network mode, check processes to find the actual listening port
          container_pid=$(podman inspect --format '{{.State.Pid}}' $container)
          if [ -n "$container_pid" ] && [ "$container_pid" != "0" ]; then
            # Try to find the main process of the container
            main_pid=$(ps --ppid $container_pid -o pid= | tr -d ' ' | head -1)
            if [ -z "$main_pid" ]; then
              main_pid=$container_pid
            fi
            
            # Find port by checking listening sockets for this PID and its children
            port=$(ss -tulpn | grep -E "pid=$main_pid|pid=$(pgrep -P $main_pid | tr '\n' ',' | sed 's/,$//'),|pid=$(pgrep -P $(pgrep -P $main_pid) | tr '\n' ',' | sed 's/,$//')" | head -1 | awk '{print $5}' | cut -d':' -f2)
            
            # Fall back to the known default ports for common applications if no port found
            if [ -z "$port" ]; then
              case "$container" in
                "sabnzbd") port="8080" ;;
                "sonarr") port="8989" ;;
                "radarr") port="7878" ;;
                # Add other known defaults as needed
                *) 
                  port=$(podman inspect $container --format '{{range $p, $conf := .Config.ExposedPorts}}{{index (split $p "/") 0}}{{break}}{{end}}')
                  ;;
              esac
            fi
          else
            # If we can't get the PID, fall back to exposed ports
            port=$(podman inspect $container --format '{{range $p, $conf := .Config.ExposedPorts}}{{index (split $p "/") 0}}{{break}}{{end}}')
          fi
        else
          # For regular network mode, get port from port mappings
          port_info=$(podman port $container | head -1)
          
          # If no port info is available, try to get exposed port from container config
          if [ -z "$port_info" ]; then
            port=$(podman inspect $container --format '{{range $p, $conf := .Config.ExposedPorts}}{{index (split $p "/") 0}}{{break}}{{end}}')
          else
            # Extract port number from port info
            port=$(echo $port_info | awk '{print $3}' | cut -d':' -f2)
          fi
        fi
        
        # Add a note for containers with host network and where we need to verify ports
        host_note=""
        if [ "$network_mode" == "host" ]; then
          host_note=" [host network]"
          
          # Verify port is actually in use (for host network containers)
          is_used=$(ss -tulpn | grep ":$port " | wc -l)
          if [ "$is_used" -eq "0" ]; then
            host_note=" [⚠️ port $port not in use]"
          fi
        fi
        
        # Construct URL
        url="http://$ip:$port$host_note"
        
        # Print container name and URL with proper alignment
        printf "%-''${max_name}s  %s\n" "$container" "$url"
        
        # Track this port if it's not empty
        if [ ! -z "$port" ]; then
          if [ -z "''${used_ports[$port]}" ]; then
            used_ports[$port]="$container"
          else
            used_ports[$port]="''${used_ports[$port]}, $container"
          fi
        fi
      done
      
      # Check for port conflicts
      conflicts=0
      for port in "${!used_ports[@]}"; do
        containers="${used_ports[$port]}"
        if [[ "$containers" == *","* ]]; then
          if [ $conflicts -eq 0 ]; then
            echo -e "\n⚠️  Port conflicts detected:"
          fi
          echo "  Port $port: $containers"
          conflicts=1
        fi
      done
    }
  '';
}