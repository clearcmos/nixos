# Git Configuration in NixOS

This document explains how Git is configured in this NixOS system, particularly for managing the NixOS configuration repository.

## Overview

The Git configuration module (`git.nix`) provides a way to automatically configure Git credentials and SSH keys for effective Git operations. This is especially useful for:

1. Managing NixOS configurations in version control
2. Enabling seamless GitHub access
3. Setting up proper user identity for commits
4. Configuring SSH keys for secure authentication

## Configuration

### Environment Variables

Git configuration is loaded from the `/etc/nixos/.env` file with the following variables:

```
# Git Configuration
GITHUB_USER=mygithubusername
GITHUB_EMAIL=user@example.com
SYSTEM_USERNAME=myusername
```

### What Gets Configured

The module sets up:

1. **Git User Identity**: Sets the user.name and user.email for system-wide Git configuration
2. **SSH Configuration**: Creates SSH configs to use the correct keys for GitHub
3. **Key Access**: Displays the public keys for easy addition to GitHub

## Implementation Details

### Configuration Files

The module creates or updates:

- `/etc/gitconfig`: System-wide Git configuration
- `/root/.ssh/config`: SSH configuration for the root user
- `/home/<username>/.ssh/config`: SSH configuration for the regular user

### SSH Key Setup

SSH configs are set up to use the following keys:

```
Host github.com
  IdentityFile /path/to/.ssh/id_ed25519
  User git
```

This ensures that Git operations use the correct SSH keys when connecting to GitHub.

### Helper Tool

The module adds a helper tool to the system:

- `show-github-keys`: A command-line utility to display the public keys for both root and the regular user

## Usage

### Adding Keys to GitHub

After the system is set up, you should:

1. Run `show-github-keys` to display the public SSH keys
2. Add these keys to your GitHub account's SSH keys section
3. Test the connection with `ssh -T git@github.com`

### Working with Git Repositories

To clone repositories using SSH:

```bash
git clone git@github.com:username/repository.git
```

Push changes using the configured identity:

```bash
git push origin main
```

## Troubleshooting

If you encounter issues with Git:

1. Check that the SSH keys exist: `ls -la ~/.ssh/`
2. Verify SSH configuration: `cat ~/.ssh/config`
3. Test GitHub connection: `ssh -T git@github.com`
4. Check Git identity configuration: `git config --list`