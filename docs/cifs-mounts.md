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

2. **Activation Scripts**:
   - `cifsCredentials`: Creates secure credential files from environment variables
   - `cifsMountPoints`: Creates directory mount points
   - `cifsMountSetup`: Prepares for mounting by unmounting any existing shares
   - `cifsMount`: Performs the actual mounting of CIFS shares

### Mount Points

The following mount points are configured:

- `/mnt/bedro`: User directory from host 1 (MSI)
- `/mnt/d`: Data drive from host 1 (MSI)
- `/mnt/syno`: Primary share from host 2 (Synology)
- `/mnt/syno-backups`: Backup share from host 2 (Synology)

## How It Works

The CIFS mounts are implemented using NixOS activation scripts rather than the declarative `fileSystems` configuration. This approach offers several advantages:

1. **Credential Security**: Credentials are securely stored in `.env` and only read during the activation phase
2. **Error Handling**: The scripts include proper error handling and diagnostics
3. **Flexibility**: Mount options are customized per share
4. **Reliability**: Mounting happens after all required components are initialized

## Process Flow

During system activation (when running `nixos-rebuild switch`):

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

1. Check credential files in `/etc/.msi` and `/etc/.syno`
2. Verify network connectivity to the CIFS servers
3. Check system logs using `journalctl -u 'systemd-fsck*' -u 'systemd-remount*'`
4. Manually attempt mounting using the same credentials to test
5. Examine kernel logs with `dmesg | grep -i cifs`

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
