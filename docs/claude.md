# Claude Code Configuration in NixOS

This document explains how Claude Code is installed and configured in this NixOS system.

## Overview

The Claude module (`claude.nix`) provides:

1. Automated installation of Claude Code via npm
2. Secure handling of Claude API credentials
3. Configuration file management across system reboots
4. Command line access to Claude through a wrapper script

## Configuration

### Environment Variables

Claude configuration is stored in the `/etc/nixos/.env` file with variables like:

```
# CLAUDE
PRIMARY_API_KEY=sk-ant-api03-xxxxxxxxxxxx
USER_ID=xxxxxxxxxxxx
ACCOUNT_UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
EMAIL_ADDRESS=user@example.com
ORGANIZATION_UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
ORGANIZATION_ROLE=admin
WORKSPACE_ROLE=workspace_developer
APPROVED_API_KEY=xxxxxxxxxxxx
HAS_COMPLETED_ONBOARDING=true
LAST_ONBOARDING_VERSION=0.2.64
PROJECT_PATH=/home/username
LAST_COST=0
LAST_API_DURATION=0
LAST_DURATION=24997
LAST_LINES_ADDED=0
LAST_LINES_REMOVED=0
LAST_SESSION_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
NUM_STARTUPS=1
```

### Configuration Files

Claude configuration is maintained in these locations:

- `/etc/nixos/private/.claude.json`: Source configuration file
- `/home/<username>/.claude.json`: User-specific configuration
- `/home/<username>/.claude/config.json`: Alternate configuration location
- `/root/.claude.json`: Configuration for the root user

## Installation Process

Claude Code is installed through these mechanisms:

1. **NPM Global Installation**: The module installs Claude Code globally via npm
2. **Global PATH Configuration**: Ensures the Claude binary is available in the system PATH
3. **Wrapper Script**: Provides a `claude` command that checks for proper installation

## Implementation Details

### Service Components

The module creates several systemd services:

1. **claude-code-install**: Installs Claude Code globally via npm
2. **claude-config-setup**: Sets up the initial configuration files
3. **claude-config-copy**: Ensures configuration files exist at boot time

### Command-line Access

To access Claude Code from the command line:

```bash
claude
```

This command uses the wrapper script to ensure proper environment setup before launching Claude Code.

### Configuration Management

Configuration files are maintained through:

1. An activation script that runs during each `nixos-rebuild`
2. A systemd service that runs at boot time
3. A dedicated path for npm global packages in `/opt/npm-global`

## Troubleshooting

If you encounter issues with Claude Code:

1. Check the installation service status:
   ```bash
   systemctl status claude-code-install
   ```

2. Verify configuration files exist:
   ```bash
   ls -la ~/.claude.json ~/.claude/config.json
   ```

3. Check npm global installation:
   ```bash
   ls -la /opt/npm-global/bin/claude
   ```

4. See if the wrapper script is working:
   ```bash
   which claude
   ```

If Claude fails to start, check that the API key in the `.env` file is valid and that configuration files are properly set up.