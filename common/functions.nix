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
        # Get port information
        port_info=$(podman port $container | head -1)
        
        # If no port info is available, try to get exposed port from container config
        if [ -z "$port_info" ]; then
          port=$(podman inspect $container --format '{{range $p, $conf := .Config.ExposedPorts}}{{index (split $p "/") 0}}{{break}}{{end}}')
        else
          # Extract port number from port info
          port=$(echo $port_info | awk '{print $3}' | cut -d':' -f2)
        fi
        
        # Construct URL
        url="http://$ip:$port"
        
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
      for port in "''${!used_ports[@]}"; do
        containers="''${used_ports[$port]}"
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