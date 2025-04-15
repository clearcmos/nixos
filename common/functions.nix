{
  # Define shell functions for bash
  programs.bash.interactiveShellInit = ''
    pman() {
      # Get local IP address
      ip=$(ip route get 1.1.1.1 | awk '{print $7; exit}')

      # Get container information
      echo "Container URLs:"
      echo "---------------"
      
      podman ps --format "json" | jq -c '.[]' | while read -r container_json; do
        # Extract container name and ports
        container=$(echo "$container_json" | jq -r '.Names')
        ports=$(echo "$container_json" | jq -r '.Ports')
        
        # Skip containers with no ports
        if [[ "$ports" == "" ]]; then
          continue
        fi
        
        # Extract public port mapping
        if [[ "$ports" == *"->"* && "$ports" == *":"* ]]; then
          # Extract host port (format like 0.0.0.0:9000->9000/tcp or 8082->8080/tcp)
          port=$(echo "$ports" | grep -o '[0-9.]*:[0-9]\+->.*\|[0-9]\+->.*' | head -1 | sed -E 's/^([0-9.]*:)?([0-9]+)->.*$/\2/')
          
          # Print clickable link
          if [ -n "$port" ]; then
            echo "$container: http://$ip:$port"
          fi
        else
          # For containers with exposed ports but no host mapping
          internal_port=$(echo "$ports" | grep -o '[0-9]\+/tcp' | head -1 | sed 's|/tcp||')
          
          if [ -n "$internal_port" ]; then
            # Show port as internal only
            echo "$container: http://$ip:$internal_port (internal only)"
          fi
        fi
      done
    }
  '';
}