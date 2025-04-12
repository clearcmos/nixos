# NixOS User Management

This document explains how user accounts are configured and managed in this NixOS system.

## Overview

The user management configuration is implemented through the `users.nix` module, which provides a centralized way to:

1. Create and configure the main system user
2. Set up SSH keys for both the main user and root
3. Configure SSH access controls
4. Manage user passwords securely

## Configuration

### Environment Variables

User configuration is primarily loaded from the `/etc/nixos/.env` file, which can include:

```
# User Configuration
SYSTEM_USERNAME=myusername
SYSTEM_PASSWORD=mypassword
SSH_AUTHORIZED_KEY=ssh-ed25519 AAAAC3NzaC1lZDI...
GITHUB_USER=mygithubusername
GITHUB_EMAIL=user@example.com
```

### Module Options

The module provides the following options:

- `mainUser.username`: The username of the main system user, which can be referenced by other modules

### User Account Features

The created user account includes:

1. **Administrative Access**: Added to the `wheel` group for sudo access
2. **SSH Authentication**: SSH keys configured from the `.env` file
3. **Password Authentication**: Optional password authentication from the `.env` file
4. **Home Directory**: Automatic creation of the user's home directory

## SSH Configuration

The module implements several SSH-related features:

### SSH Keys

- **Authorized Keys**: Sets up authorized keys for both the main user and root
- **SSH Key Generation**: Automatically generates SSH keys with correct usernames and hostnames
- **Key Regeneration Prevention**: Preserves existing keys but updates comments if needed

### SSH Access Control

The module configures SSH access rules:

```
# Allow regular user from anywhere
AllowUsers <username>

# Allow root only from local network
Match Address 192.168.1.0/24
    AllowUsers root
```

## Implementation Details

### Component Services

The module creates several systemd services:

1. **setup-root-ssh-key**: Configures SSH authorized keys for the root user
2. **setup-user-ssh-key**: Configures SSH authorized keys for the main user
3. **generate-ssh-keys**: Generates SSH keys for both users with proper naming

### Integration with Other Modules

The `users.nix` module works with other modules by:

1. Exposing the mainUser.username option to be used by other modules
2. Reading configuration from the shared .env file
3. Ensuring SSH keys are properly set up for Git and other services

## Customization

To customize user configuration:

1. Edit the variables in `/etc/nixos/.env` to change usernames, passwords, or SSH keys
2. For more advanced customization, modify the `users.nix` module directly

## Troubleshooting

If you encounter user-related issues:

1. Check that the `.env` file exists and contains the required variables
2. Verify that SSH keys have been properly generated: `ls -la /home/<username>/.ssh/`
3. Confirm user permissions: `ls -la /home/<username>/`
4. Try SSH access: `ssh <username>@localhost`