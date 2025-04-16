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

    pupdate() {
      # Get current week in YYYYWW format
      CURRENT_WEEK=$(date +%Y%U)
      echo "Current week: $CURRENT_WEEK"
      echo ""
      
      # Find containers that need updates
      NEEDS_UPDATE=0
      echo "Checking containers for updates..."
      
      for service in $(systemctl list-units --type=service | grep podman-compose | awk '{print $1}'); do
        # Extract project name from service name
        project=$(echo $service | sed 's/podman-compose-\(.*\)\.service/\1/')
        last_pull_file="/var/lib/containers/storage/volumes/$project/.last_pull"
        
        # Check if update is needed
        if [ ! -f "$last_pull_file" ] || [ "$(cat $last_pull_file 2>/dev/null)" != "$CURRENT_WEEK" ]; then
          last_pull=$(cat $last_pull_file 2>/dev/null || echo "never")
          echo "Updating: $project (last pull: $last_pull)"
          
          # Restart service to trigger update
          systemctl restart $service
          NEEDS_UPDATE=1
          
          # Wait briefly to avoid overwhelming the system
          sleep 2
        fi
      done
      
      if [ $NEEDS_UPDATE -eq 0 ]; then
        echo "All containers are up-to-date (last pulled this week)."
      else
        echo ""
        echo "Update process initiated. Check 'journalctl -fu podman-compose-*' for details."
      fi
    }
  '';
}