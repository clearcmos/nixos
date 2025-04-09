# NixOS Container Management Documentation

This document explains how the container management system works in this NixOS configuration, including the conversion process from Docker Compose YAML files to NixOS container configurations.

## Table of Contents

1. [Overview](#overview)
2. [Directory Structure](#directory-structure)
3. [The Conversion Process](#the-conversion-process)
4. [The `compose2nix-wrapper.sh` Script](#the-compose2nix-wrappersh-script)
5. [Generated Nix File Structure](#generated-nix-file-structure)
6. [Volume Management](#volume-management)
7. [Image Pulling Behavior](#image-pulling-behavior)
8. [Container Management Commands](#container-management-commands)
9. [Examples](#examples)
10. [Troubleshooting](#troubleshooting)

## Overview

This system provides a workflow to convert Docker Compose YAML files to NixOS container configurations using Podman as the backend. The conversion process automatically handles:

- Container definitions with proper image references
- Volume mounts with automatic directory creation
- Network configurations
- Port mappings
- Container capabilities and device access
- Image pulling during system activation
- Proper systemd integration

## Directory Structure

The system uses the following directory structure:

- `/etc/nixos/docker-compose/` - Source Docker Compose YAML files
- `/etc/nixos/containers/` - Generated NixOS container configuration files
- `/etc/nixos/scripts/compose2nix-wrapper.sh` - The conversion script
- `/var/lib/containers/storage/volumes/` - Container persistent volumes

## The Conversion Process

The workflow for adding a new container is:

1. Create a Docker Compose YAML file in `/etc/nixos/docker-compose/`
2. Run the conversion script: `cd /etc/nixos/scripts && bash compose2nix-wrapper.sh`
3. Apply the changes: `sudo nixos-rebuild switch`

The script will generate appropriate NixOS configuration files that define the containers using Podman and integrate them with systemd.

## The `compose2nix-wrapper.sh` Script

The `compose2nix-wrapper.sh` script handles the conversion process from Docker Compose YAML to NixOS configurations. Key features include:

- Uses `compose2nix` (a Nix utility) as the base converter
- Enhances the generated files with additional capabilities
- Handles relative paths in volume definitions
- Creates systemd tmpfiles rules for required directories
- Adds automatic image pulling during system rebuilds
- Creates separate systemd services for manual image pulling

The script processes each YAML file in `/etc/nixos/docker-compose/` and generates a corresponding Nix file in `/etc/nixos/containers/`.

### Path Resolution

The script handles different types of paths in Docker Compose volume definitions:

- **Relative paths** (`./config:/container/path`): Converted to absolute paths under `/var/lib/containers/storage/volumes/$PROJECT_NAME/`
- **Home directory paths** (`/home/user/data:/container/path`): Redirected to `/var/lib/containers/storage/volumes/$PROJECT_NAME/`
- **Non-existent paths** under `/etc/nixos/`: Redirected to `/var/lib/containers/storage/volumes/$PROJECT_NAME/`
- **Absolute paths** to existing directories: Preserved as-is

## Generated Nix File Structure

The generated Nix files include several components:

### Directory Creation Rules

```nix
systemd.tmpfiles.rules = [
  "d /var/lib/containers/storage/volumes/project_name/volume_path 0755 root root - -"
];
```

### Image Pull Services

```nix
systemd.services."pull-project-image-tag-image" = {
  description = "Pull latest image:tag image for project";
  path = [ pkgs.podman ];
  script = ''
    podman pull image:tag
  '';
  serviceConfig = {
    Type = "oneshot";
  };
  wantedBy = [ "multi-user.target" ];
};
```

### Activation Scripts

```nix
system.activationScripts.pullprojectContainers = ''
  echo "Pulling latest image for project/container..."
  ${pkgs.podman}/bin/podman pull image:tag || true
  echo "Done pulling for project/container."
'';
```

### Container Definitions

```nix
virtualisation.oci-containers.containers."container-name" = {
  image = "image:tag";
  volumes = [
    "/path/on/host:/path/in/container:rw"
  ];
  ports = [
    "8080:8080/tcp"
  ];
  log-driver = "journald";
  extraOptions = [
    "--cap-add=SYS_ADMIN"
    "--device=/dev/sda:/dev/sda:rwm"
  ];
};
```

### Service Dependencies

```nix
systemd.services."podman-container-name" = {
  serviceConfig = {
    Restart = lib.mkOverride 90 "no";
  };
  after = [
    "podman-network-project_default.service"
  ];
  requires = [
    "podman-network-project_default.service"
  ];
  partOf = [
    "podman-compose-project-root.target"
  ];
  wantedBy = [
    "podman-compose-project-root.target"
  ];
};
```

### Network Configuration

```nix
systemd.services."podman-network-project_default" = {
  path = [ pkgs.podman ];
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    ExecStop = "podman network rm -f project_default";
  };
  script = ''
    podman network inspect project_default || podman network create project_default
  '';
  partOf = [ "podman-compose-project-root.target" ];
  wantedBy = [ "podman-compose-project-root.target" ];
};
```

### Root Target

```nix
systemd.targets."podman-compose-project-root" = {
  unitConfig = {
    Description = "Root target generated by compose2nix.";
  };
  wantedBy = [ "multi-user.target" ];
};
```

## Volume Management

The script creates proper volume directories under `/var/lib/containers/storage/volumes/$PROJECT_NAME/` for persistent storage:

- Directories are automatically created during system activation if they don't exist
- Existing data is preserved across rebuilds
- Directory permissions are set to 0755 (root:root) by default

## Image Pulling Behavior

Image pulling happens in two ways:

1. **Automatic pulling** during system rebuilds via activation scripts
   - Runs during every `nixos-rebuild switch` or `nixos-rebuild test`
   - Pulls the latest image but doesn't restart running containers

2. **Manual pulling** via dedicated systemd services
   - Can be triggered manually: `systemctl start pull-project-image-tag-image.service`
   - Useful for updating images without a system rebuild

Note: Containers will only use newly pulled images after they are restarted.

## Container Management Commands

Common operations you can perform:

### Check Container Status

```bash
# View status of a specific container
systemctl status podman-container-name.service

# List all running containers
podman ps

# List all containers (including stopped ones)
podman ps -a
```

### Container Lifecycle Management

```bash
# Start a container
systemctl start podman-container-name.service

# Stop a container
systemctl stop podman-container-name.service

# Restart a container (to use a newly pulled image)
systemctl restart podman-container-name.service

# Enable a container to start at boot
systemctl enable podman-container-name.service

# Disable a container from starting at boot
systemctl disable podman-container-name.service
```

### Image Management

```bash
# Pull the latest image manually
systemctl start pull-project-image-tag-image.service

# List all downloaded images
podman images

# Remove an image
podman rmi image:tag
```

### Container Logs

```bash
# View container logs
journalctl -u podman-container-name.service

# Follow container logs in real-time
journalctl -u podman-container-name.service -f
```

### Network Management

```bash
# List container networks
podman network ls

# Inspect a network
podman network inspect project_default
```

## Examples

### Example 1: Managing the Scrutiny Container

The scrutiny container monitors hard drive health. Here's how to manage it:

```bash
# Check scrutiny container status
systemctl status podman-scrutiny.service

# Restart the scrutiny container (to use a newly pulled image)
systemctl restart podman-scrutiny.service

# View scrutiny logs
journalctl -u podman-scrutiny.service -f

# Manually pull the latest scrutiny image
systemctl start pull-scrutiny-scrutiny-master-omnibus-image.service
```

### Example 2: Managing the Glances Container

Glances provides system monitoring. Here's how to manage it:

```bash
# Check glances container status
systemctl status podman-glances.service

# Restart the glances container
systemctl restart podman-glances.service

# View glances logs
journalctl -u podman-glances.service -f

# Manually pull the latest glances image
systemctl start pull-glances-glances-latest-full-image.service
```

### Example 3: Adding a New Container

To add a new PostgreSQL container:

1. Create `/etc/nixos/docker-compose/postgres.yml`:

```yaml
version: '3.8'

services:
  db:
    container_name: postgres
    image: postgres:15
    environment:
      POSTGRES_PASSWORD: example
      POSTGRES_USER: user
      POSTGRES_DB: mydb
    volumes:
      - ./data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    restart: unless-stopped
```

2. Run the conversion script:

```bash
cd /etc/nixos/scripts && bash compose2nix-wrapper.sh
```

3. Apply the changes:

```bash
sudo nixos-rebuild switch
```

4. The container will be started automatically, and the data will be stored in `/var/lib/containers/storage/volumes/postgres/data/`.

## Troubleshooting

### Common Issues

#### Container Fails to Start Due to Missing Directories

If a container fails with an error like `statfs /path/to/dir: no such file or directory`, the volume directory does not exist. Options:

1. Update and run the conversion script again
2. Manually create the directory: `sudo mkdir -p /path/to/dir`
3. Restart the container: `systemctl restart podman-container-name.service`

#### Container Uses Old Image After Rebuild

Remember that rebuilding the system pulls the latest images but doesn't restart containers. To use a new image:

```bash
systemctl restart podman-container-name.service
```

#### Network Issues Between Containers

Make sure containers that need to communicate are on the same network:

```bash
podman network inspect project_default
```

To manually add a container to a network:

```bash
podman network connect project_default container-name
```

#### Checking Container Logs for Errors

View detailed logs to diagnose issues:

```bash
journalctl -u podman-container-name.service -n 100
```

#### Container Volume Permissions

If a container can't write to a volume, check the permissions:

```bash
ls -la /var/lib/containers/storage/volumes/project_name/volume_path
```

You may need to adjust permissions:

```bash
sudo chmod -R 755 /var/lib/containers/storage/volumes/project_name/volume_path
sudo chown -R root:root /var/lib/containers/storage/volumes/project_name/volume_path
```

Or set specific permissions based on the container's needs (e.g., for a database container).