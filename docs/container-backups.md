# Container Volume Backups

This document describes the container volume backup system used in this NixOS configuration.

## Overview

The backup script `/etc/nixos/scripts/backup-containers.sh` is designed to safely backup all Podman container volumes. It performs a complete shutdown of all running containers before backing up to ensure data consistency, then restarts them afterward.

## Backup Process

1. **Save Container Configurations**: Stores running container configurations for proper restoration
2. **Stop Containers**: All running containers are gracefully stopped
3. **Backup Volumes**: All volumes in `/var/lib/containers/storage/volumes/` are archived to a timestamped file
4. **Restart Containers**: Previously running containers are restarted automatically, with recreation if needed
5. **Prune Old Backups**: Maintains a rolling set of backups (default: 8 maximum)

## Backup Location

Backups are stored at:
```
/mnt/syno/backups/misc/container-volumes/container-volumes-YYYYMMDD-HHMMSS.tar.gz
```

## Usage

```bash
# Run backup manually
sudo /etc/nixos/scripts/backup-containers.sh

# Schedule with cron (example: daily at 2:30 AM)
# 30 2 * * * root /etc/nixos/scripts/backup-containers.sh
```

## Configuration

The following variables can be modified in the script:

| Variable | Default | Description |
|----------|---------|-------------|
| `VOLUMES_DIR` | `/var/lib/containers/storage/volumes` | Source directory for volumes |
| `BACKUP_DIR` | `/mnt/syno/backups/misc/container-volumes` | Target directory for backups |
| `MAX_BACKUPS` | `8` | Number of backup files to keep |
| `LOG_FILE` | `/var/log/container-backup.log` | Path to log file |

## Container Recreation

The backup script includes container recreation logic when containers cannot be restarted directly:

1. Container configurations are saved before stopping
2. If a direct restart fails, the script will:
   - Extract image information from the saved configuration
   - Extract port mappings, environment variables, and volume mounts
   - Recreate the container with the same configuration
   - Start the recreated container

## Restoring from Backup

To restore container volumes from a backup:

1. Stop all running containers:
   ```bash
   podman stop -a
   ```

2. Extract the backup to the volumes directory:
   ```bash
   sudo tar -xzf /path/to/backup/container-volumes-YYYYMMDD-HHMMSS.tar.gz -C /var/lib/containers/storage/volumes/
   ```

3. Fix permissions if needed:
   ```bash
   sudo chown -R root:root /var/lib/containers/storage/volumes/
   ```

4. Restart containers:
   ```bash
   # For systemd-managed containers
   sudo systemctl start podman-compose-sonarr-root.target
   sudo systemctl start podman-compose-scrutiny-root.target
   # etc. for other containers
   ```

## Logs

The backup script logs all operations to `/var/log/container-backup.log`, including:
- Container configuration saving
- Container stop/start events
- Backup creation status
- Container recreation attempts
- Error conditions
- Backup file management

## Notes

- The backup process will temporarily interrupt services while containers are stopped
- Schedule backups during low-usage periods
- Backup files are compressed to save space but may still be large
- Configure the backup retention (`MAX_BACKUPS`) based on your storage capacity