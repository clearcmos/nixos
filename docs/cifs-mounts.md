# CIFS Mounts in NixOS

This document explains how CIFS (Common Internet File System) shares are configured and mounted in this NixOS setup.

## Overview

The system uses a custom NixOS module that securely mounts network shares using CIFS (SMB/Samba) during system activation. This approach ensures credentials are handled securely while allowing the mounts to be managed as part of the NixOS configuration.

## Configuration

### Environment Variables

CIFS mount configuration is stored in the `/etc/nixos/.env` file with the following variables:

```
# CIFS Shares Configuration
CIFS_HOST_1=msi.home.arpa
CIFS_HOST_2=syno.home.arpa
CIFS_HOST_1_SHARE_1=bedro
CIFS_HOST_1_SHARE_2=d
CIFS_HOST_2_SHARE_1=syno
CIFS_HOST_2_SHARE_2=syno-backups
CIFS_HOST_1_USER=myuser
CIFS_HOST_1_PASS=<password>
CIFS_HOST_2_USER=myuser
CIFS_HOST_2_PASS=<password>
```

### Module Structure

The CIFS mount functionality is implemented in `/etc/nixos/modules/cifs-mounts.nix` and includes:

1. **Module Options**:
   - `cifsShares.enable`: Boolean to enable/disable all CIFS mounts
   - `cifsShares.createMountPoints`: Boolean to automatically create mount points
   - `cifsShares.skipIfMounted`: Boolean to skip remounting if shares are already mounted

2. **Components**:
   - **Activation Scripts**:
     - `cifsCredentials`: Creates secure credential files from environment variables
     - `cifsMountPoints`: Creates directory mount points
   - **Systemd Service**:
     - `mount-cifs-shares.service`: Handles the actual mounting of CIFS shares

### Mount Points

The following mount points are configured:

- `/mnt/bedro`: User directory from host 1 (MSI)
- `/mnt/d`: Data drive from host 1 (MSI)
- `/mnt/syno`: Primary share from host 2 (Synology)
- `/mnt/syno-backups`: Backup share from host 2 (Synology)

## How It Works

The CIFS mounts are implemented using a systemd service rather than the declarative `fileSystems` configuration. This approach offers several advantages:

1. **Credential Security**: Credentials are securely stored in `.env` and only read during service execution
2. **Error Handling**: The service includes proper error handling and diagnostics
3. **Flexibility**: Mount options are customized per share
4. **Reliability**: Mounting happens after network is online and other required components are initialized

## Process Flow

CIFS mounts are implemented via a systemd service (`mount-cifs-shares`) that runs during system startup:

1. The system reads mount configuration from the environment file
2. Credential files are created in `/etc/.msi` and `/etc/.syno` with restricted permissions (mode 600)
3. Mount points are created in `/mnt/` if they don't exist
4. Any existing mounts are cleanly unmounted
5. Shares are mounted using the appropriate credentials and options
6. Mount status is verified and reported

## Customization

To customize the CIFS mounts:

1. Edit the variables in `/etc/nixos/.env` to change server addresses, share names, or credentials
2. Enable/disable CIFS mounts by setting `cifsShares.enable = true/false` in your host configuration
3. Adjust mount options in `cifs-mounts.nix` if needed (e.g., for different protocols or performance settings)

## Troubleshooting

If mounts aren't working correctly:

1. Check if the mount service is running: `systemctl status mount-cifs-shares.service`
2. Check service logs: `journalctl -u mount-cifs-shares.service`
3. Check credential files in `/etc/.msi` and `/etc/.syno`
4. Verify network connectivity to the CIFS servers
5. Ensure the module is imported and enabled in your configuration (add `cifsShares.enable = true;`)
6. Manually attempt mounting using the same credentials to test
7. Examine kernel logs with `dmesg | grep -i cifs`

## Manual Mounting

To manually mount or remount the shares, use:

```bash
# For MSI shares
mount -t cifs -o credentials=/etc/.msi,uid=<username>,gid=users,vers=2.1 //msi.home.arpa/bedro /mnt/bedro
mount -t cifs -o credentials=/etc/.msi,uid=<username>,gid=users,vers=2.1 //msi.home.arpa/d /mnt/d

# For Synology shares
mount -t cifs -o credentials=/etc/.syno,uid=<username>,gid=users,vers=2.1 //syno.home.arpa/syno /mnt/syno
mount -t cifs -o credentials=/etc/.syno,uid=<username>,gid=users,vers=2.1 //syno.home.arpa/syno-backups /mnt/syno-backups
```

Replace `<username>` with the current system username.
