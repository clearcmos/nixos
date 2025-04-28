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
}
