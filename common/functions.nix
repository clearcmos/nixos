{
  # Define shell functions for bash
  programs.bash.interactiveShellInit = ''
    pman() {
      # Get local IP address
      ip=$(ip route get 1.1.1.1 | awk '{print $7; exit}')

      # Get container information
      echo "Container URLs:"
      echo "---------------"
      
      podman ps --format "table {{.Names}}\t{{.Ports}}" | tail -n +2 | while read -r container ports; do
        # Extract port mapping if available
        port=""
        if [[ "$ports" == *":"* ]]; then
          # Extract public port from mappings
          port=$(echo "$ports" | grep -o '[0-9]\+:[0-9]\+' | head -1 | cut -d':' -f1)
        else
          # No port mapping found, try to get it from container config
          container_port=$(podman inspect "$container" --format '{{range $p, $conf := .Config.ExposedPorts}}{{index (split $p "/") 0}}{{break}}{{end}}')
          
          if [ -n "$container_port" ]; then
            # For containers with exposed ports but no port mapping, use the exposed port
            port="$container_port"
          fi
        fi
        
        # Skip containers with no detectable port
        if [ -n "$port" ]; then
          # Print clickable link
          echo "$container: http://$ip:$port"
        fi
      done
    }
  '';
}