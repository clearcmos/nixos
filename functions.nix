# Custom functions for NixOS
{ config, lib, pkgs, ... }:

{
  # Systemd service and timer for backing up NixOS configuration
  systemd.services.synonix = {
    description = "Backup NixOS configuration to Synology";
    script = ''
      # Create timestamp for the backup filename
      TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
      BACKUP_DIR="/mnt/syno/backups/nixos"
      BACKUP_FILE="$BACKUP_DIR/nixos_$TIMESTAMP.tar.gz"
      
      # Ensure backup directory exists
      mkdir -p "$BACKUP_DIR"
      
      # Create backup - include all files, including hidden ones
      tar -czf "$BACKUP_FILE" -C /etc nixos
      
      # Keep only the latest 14 backups
      cd "$BACKUP_DIR" && ls -t nixos_*.tar.gz | tail -n +15 | xargs -r rm
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    path = with pkgs; [
      coreutils
      gnutar
      gzip
      findutils
    ];
  };

  # Timer to run the backup service daily
  systemd.timers.synonix = {
    description = "Timer for NixOS configuration backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  # Shell functions for managing NixOS
  environment.shellAliases = {
    generations = ''
      generations() {
          local profile="/nix/var/nix/profiles/system"
          echo "Listing all NixOS system generations:"
          nix-env --list-generations --profile "$profile" | tee /tmp/nixos_generations_list
          # Extract generation numbers (sorted ascending)
          local gens
          gens=($(awk '{print $1}' /tmp/nixos_generations_list | grep -E '^[0-9]+' | sort -n))
          if [ ''${#gens[@]} -eq 0 ]; then
              echo "No generations found."
              return 1
          fi
          local most_recent="''${gens[-1]}"
          local oldest="''${gens[0]}"
          
          echo
          echo "Enter generation numbers to delete (space-separated), or type 'all' to delete all except the most recent (''${most_recent}):"
          read -r input
          if [[ "$input" == "all" ]]; then
              if [ ''${#gens[@]} -le 1 ]; then
                  echo "Only one generation exists. Nothing to delete."
                  return 0
              fi
              echo "Deleting all generations except the most recent..."
              # Delete all except the current generation
              sudo nix-env --profile "$profile" --delete-generations old
          else
              # Split input by spaces into array
              read -ra selected <<< "$input"
              for gen in "''${selected[@]}"; do
                  if [[ ! " ''${gens[*]} " =~ " $gen " ]]; then
                      echo "Generation $gen not found."
                      return 1
                  fi
              done
              echo "Deleting generations: ''${selected[*]}"
              sudo nix-env --profile "$profile" --delete-generations "''${selected[@]}"
          fi
          echo "Updating bootloader entries..."
          sudo nixos-rebuild boot
          echo "Done."
      }
    '';

    searchpkg = ''
      nixpkg-search() {
        echo "Enter package name to search for:"
        read pkg
        
        # Run the search command and capture the output
        output=$(nix search nixpkgs "$pkg" --extra-experimental-features 'nix-command flakes')
        
        # Process the output to extract package names
        echo "$output" | grep -o "legacyPackages.x86_64-linux.[^ ]*" | sed 's/legacyPackages.x86_64-linux\\./pkgs./' | sort
      }
    '';

    gc = ''
      gc() {
          echo "Checking how much space would be freed by garbage collection..."
          
          # Create a temporary file for the dry run output
          local tmpfile=$(mktemp)
          
          # Run dry-run and capture the output
          sudo nix-collect-garbage --dry-run > "$tmpfile"
          
          # Count the number of paths that would be deleted
          local path_count=$(grep -c "^Would delete" "$tmpfile")
          
          # Calculate total size by adding up all the numbers followed by "B", "KiB", "MiB", "GiB"
          local total_bytes=0
          
          # Process each size unit separately and convert to bytes
          while read -r line; do
              size=$(echo "$line" | grep -o '[0-9.]\+ [KMGT]iB\|[0-9]\+ B' | sed 's/[[:space:]].*//')
              unit=$(echo "$line" | grep -o '[KMGT]iB\|B')
              
              case "$unit" in
                  "B")
                      bytes=$size
                      ;;
                  "KiB")
                      bytes=$(echo "$size * 1024" | bc)
                      ;;
                  "MiB")
                      bytes=$(echo "$size * 1024 * 1024" | bc)
                      ;;
                  "GiB")
                      bytes=$(echo "$size * 1024 * 1024 * 1024" | bc)
                      ;;
                  "TiB")
                      bytes=$(echo "$size * 1024 * 1024 * 1024 * 1024" | bc)
                      ;;
              esac
              
              total_bytes=$(echo "$total_bytes + ''${bytes%%.*}" | bc)
          done < <(grep "would be deleted" "$tmpfile")
          
          # Convert total bytes to human readable format
          if [ "$total_bytes" -lt 1024 ]; then
              total_hr="''${total_bytes} B"
          elif [ "$total_bytes" -lt 1048576 ]; then
              total_hr="$(echo "scale=2; $total_bytes/1024" | bc) KiB"
          elif [ "$total_bytes" -lt 1073741824 ]; then
              total_hr="$(echo "scale=2; $total_bytes/1048576" | bc) MiB"
          else
              total_hr="$(echo "scale=2; $total_bytes/1073741824" | bc) GiB"
          fi
          
          echo "Garbage collection would free approximately $total_hr from $path_count path(s)"
          echo
          echo "Run 'sudo nix-collect-garbage' to actually free this space"
          
          # Clean up
          rm "$tmpfile"
      }
    '';
  };
}
