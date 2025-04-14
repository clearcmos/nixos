# Container Management with Podman Compose

This directory contains Docker Compose YAML files that are directly managed by Podman Compose through NixOS systemd services.

## How it works

1. Each `.yml` file in this directory is automatically detected and managed
2. A systemd service is created for each file (named `podman-compose-<filename>`)
3. Relative volume paths (`./volume_name`) are automatically mapped to:
   ```
   /var/lib/containers/storage/volumes/<yml-name>/<volume-name>
   ```
4. The services will:
   - Start containers with the latest images when not running
   - Skip if already started and no new image is available
   - Pull new images and restart containers when updates are available

## Examples

For a file named `sonarr.yml` with these volumes:
```yaml
volumes:
  - ./data:/config
  - /mnt/syno/videos/tv:/tv
```

The `./data` volume will be created at:
```
/var/lib/containers/storage/volumes/sonarr/data
```

## Usage

1. Import the module in your NixOS configuration:
   ```nix
   # In your host configuration (e.g., /etc/nixos/hosts/your-host/default.nix)
   { config, lib, pkgs, ... }:
   
   {
     imports = [
       # Other imports
       ../../modules/podman-containers.nix
     ];
   }
   ```

2. Place your Docker Compose YAML files in this directory

3. Rebuild NixOS:
   ```bash
   sudo nixos-rebuild switch
   ```

4. Test the setup:
   ```bash
   # Check if services were created
   systemctl list-units 'podman-compose-*'
   
   # View logs to ensure proper startup
   journalctl -u podman-compose-authentik
   
   # Verify container is running
   podman ps
   
   # Check volume directories were created correctly
   ls -la /var/lib/containers/storage/volumes/
   ```

## Environment Variables

Place your environment variables in `/etc/nixos/.env`. The system will automatically copy this file to each container's volume directory.

## Managing Containers

Services are named `podman-compose-<filename>` (without the .yml extension).

```bash
# List all container services
systemctl list-units 'podman-compose-*'

# Check status of a specific service
systemctl status podman-compose-sonarr

# Restart containers
systemctl restart podman-compose-sonarr

# View logs
journalctl -u podman-compose-sonarr
```

### Convenience aliases

The module adds these useful aliases:
- `plist`: List all podman-compose services
- `pstatus`: Show status of all podman-compose services
- `prestart`: Quick restart (example: `prestart sonarr`)

## Container Data

The persistent data is stored at:
```
/var/lib/containers/storage/volumes/<yml-name>/
```

## Troubleshooting

### Container Variable Expansion
For containers that use environment variables in their image names (like `${VAR_NAME:-default}`), make sure your .env file defines these variables.

Example from authentik.yml:
```yaml
image: ${AUTHENTIK_IMAGE:-ghcr.io/goauthentik/server}:${AUTHENTIK_TAG:-2024.2.2}
```

You need to define `AUTHENTIK_IMAGE` and `AUTHENTIK_TAG` in your .env file.

### Container Exit Codes
If containers exit immediately after starting, check:
1. Port conflicts - another service might be using the same port
2. Permissions - ensure volumes have proper permissions
3. Environment variables - check if required variables are missing 

You can view container logs with:
```bash
podman logs <container_name>
```