#!/usr/bin/env bash

# Exit on error
set -e

# Script to backup Podman container volumes
# Backs up volumes from /var/lib/containers/storage/volumes/ to /mnt/syno/backups/misc/
# Keeps a maximum of 8 backups

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

# Check for required dependencies
for cmd in podman jq tar; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "Error: $cmd is required but not installed. Please install it and try again."
    exit 1
  fi
done

# Configuration
VOLUMES_DIR="/var/lib/containers/storage/volumes"
BACKUP_DIR="/mnt/syno/backups/misc/container-volumes"
MAX_BACKUPS=8
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/container-volumes-${TIMESTAMP}.tar.gz"
LOG_FILE="/var/log/container-backup.log"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Log function
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting container volume backup process..."

# Check if volumes directory exists
if [ ! -d "$VOLUMES_DIR" ]; then
  log "Error: Volumes directory does not exist: $VOLUMES_DIR"
  exit 1
fi

# Store running containers
log "Checking running containers..."
mapfile -t RUNNING_CONTAINERS < <(podman ps --format "{{.Names}}")

# Create a directory to store container configurations for easier restoration
CONTAINER_CONFIG_DIR="/tmp/container_backup_configs"
mkdir -p "$CONTAINER_CONFIG_DIR"

# Save full container configuration before stopping
if [ ${#RUNNING_CONTAINERS[@]} -gt 0 ]; then
  log "Saving container configurations..."
  for container in "${RUNNING_CONTAINERS[@]}"; do
    log "Saving configuration for container: $container"
    podman inspect "$container" > "$CONTAINER_CONFIG_DIR/$container.json"
  done
fi

if [ ${#RUNNING_CONTAINERS[@]} -gt 0 ]; then
  log "Stopping running containers..."
  
  # Stop each running container
  for container in "${RUNNING_CONTAINERS[@]}"; do
    log "Stopping container: $container"
    podman stop "$container"
  done
fi

# Sleep to ensure all write operations are complete
log "Waiting for container shutdown to complete..."
sleep 5

# Perform backup
log "Creating backup archive of all volumes..."
tar -czf "$BACKUP_FILE" -C "$VOLUMES_DIR" .
BACKUP_STATUS=$?

if [ $BACKUP_STATUS -ne 0 ]; then
  log "Error: Backup failed with status $BACKUP_STATUS"
else
  log "Backup successfully created at $BACKUP_FILE"
  chmod 640 "$BACKUP_FILE"
fi

# Restart containers
if [ ${#RUNNING_CONTAINERS[@]} -gt 0 ]; then
  log "Restarting containers..."
  
  # Restart each previously running container
  RESTART_ERRORS=0
  
  for container in "${RUNNING_CONTAINERS[@]}"; do
    log "Starting container: $container"
    if podman start "$container" 2>/dev/null; then
      log "Successfully started container: $container"
    else
      # If starting fails, check if we have a saved configuration
      CONFIG_FILE="$CONTAINER_CONFIG_DIR/$container.json"
      if [[ -f "$CONFIG_FILE" ]]; then
        log "Container $container needs to be recreated from saved configuration"
        
        # Extract needed information from the config file
        IMAGE=$(jq -r '.[0].Config.Image' "$CONFIG_FILE")
        
        if [[ -n "$IMAGE" ]]; then
          log "Recreating container $container using image $IMAGE"
          
          # Extract port mappings
          PORT_ARGS=""
          PORTS=$(jq -r '.[0].HostConfig.PortBindings | keys[]' "$CONFIG_FILE" 2>/dev/null)
          for port in $PORTS; do
            HOST_PORT=$(jq -r ".[0].HostConfig.PortBindings[\"$port\"][0].HostPort" "$CONFIG_FILE" 2>/dev/null)
            if [[ -n "$HOST_PORT" && "$HOST_PORT" != "null" ]]; then
              PORT_ARGS="$PORT_ARGS -p $HOST_PORT:${port%/tcp}"
              PORT_ARGS="$PORT_ARGS -p $HOST_PORT:${port%/udp}"
            fi
          done
          
          # Extract environment variables
          ENV_ARGS=""
          ENV_VARS=$(jq -r '.[0].Config.Env[]' "$CONFIG_FILE" 2>/dev/null)
          for env in $ENV_VARS; do
            ENV_ARGS="$ENV_ARGS -e $env"
          done
          
          # Extract volumes
          VOLUME_ARGS=""
          VOLUMES=$(jq -r '.[0].HostConfig.Binds[]?' "$CONFIG_FILE" 2>/dev/null)
          for vol in $VOLUMES; do
            if [[ -n "$vol" && "$vol" != "null" ]]; then
              VOLUME_ARGS="$VOLUME_ARGS -v $vol"
            fi
          done
          
          # Create container with extracted configuration
          CREATE_CMD="podman create --name $container $PORT_ARGS $ENV_ARGS $VOLUME_ARGS $IMAGE"
          log "Running: $CREATE_CMD"
          CONTAINER_ID=$(eval "$CREATE_CMD" 2>/dev/null)
          
          if [[ -n "$CONTAINER_ID" ]]; then
            log "Container $container recreated. Starting it..."
            if podman start "$container"; then
              log "Successfully started recreated container: $container"
            else
              log "Error: Failed to start recreated container: $container"
              RESTART_ERRORS=$((RESTART_ERRORS + 1))
            fi
          else
            log "Error: Failed to recreate container: $container"
            RESTART_ERRORS=$((RESTART_ERRORS + 1))
          fi
        else
          log "Error: Failed to extract image information for container: $container"
          RESTART_ERRORS=$((RESTART_ERRORS + 1))
        fi
      else
        log "Error: No saved configuration found for container: $container"
        RESTART_ERRORS=$((RESTART_ERRORS + 1))
      fi
    fi
  done
  
  if [ $RESTART_ERRORS -gt 0 ]; then
    log "WARNING: Failed to restart $RESTART_ERRORS container(s). Please check container status."
  fi
fi

# Clean up temporary configs
log "Cleaning up temporary container configurations..."
rm -rf "$CONTAINER_CONFIG_DIR"

# Prune old backups
log "Checking for old backups to prune..."
BACKUP_COUNT=$(ls -1 "${BACKUP_DIR}"/container-volumes-*.tar.gz 2>/dev/null | wc -l)

if [ "$BACKUP_COUNT" -gt "$MAX_BACKUPS" ]; then
  NUM_TO_DELETE=$((BACKUP_COUNT - MAX_BACKUPS))
  log "Removing $NUM_TO_DELETE old backup(s)..."
  
  mapfile -t OLD_BACKUPS < <(ls -1t "${BACKUP_DIR}"/container-volumes-*.tar.gz | tail -n "$NUM_TO_DELETE")
  for old_backup in "${OLD_BACKUPS[@]}"; do
    log "Removing old backup: $old_backup"
    rm -f "$old_backup"
  done
fi

log "Backup process completed."

# Print summary
echo "------------ Backup Summary ------------"
echo "Backup location: $BACKUP_FILE"
echo "Current backup count: $(ls -1 "${BACKUP_DIR}"/container-volumes-*.tar.gz 2>/dev/null | wc -l) / $MAX_BACKUPS"
echo "Backup size: $(du -h "$BACKUP_FILE" | cut -f1)"
echo "Container restart errors: ${RESTART_ERRORS:-0}"
echo "----------------------------------------"