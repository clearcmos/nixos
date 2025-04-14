# NixOS Configuration Management

This document explains how to build, test, and deploy NixOS configurations for different hosts using the standard NixOS flake commands.

## Building and Testing Configurations

NixOS provides built-in commands for configuration management with flakes:

### Usage

```bash
nixos-rebuild <action> --flake ".#<host>"
```

Where:
- `<host>` is the name of the host configuration to use (matches a directory under `/etc/nixos/hosts/`)
- `<action>` is one of:
  - `build`: Build the configuration without activating it
  - `test`: Build and activate the configuration temporarily (reboot to revert)
  - `dry-run`: Show what would be installed/changed without making changes
  - `boot`: Build the configuration and set it as default boot option
  - `switch`: Build and permanently switch to a new configuration

### Examples

#### Perform a dry run for the "misc" host
```bash
nixos-rebuild dry-run --flake ".#misc"
```

This will show what would be installed or changed without actually making any changes.

#### Test a configuration temporarily
```bash
nixos-rebuild test --flake ".#misc"
```

This will build and activate the configuration for the "misc" host temporarily. The changes will be reverted upon reboot.

#### Build a configuration without activating it
```bash
nixos-rebuild build --flake ".#misc"
```

This builds the configuration but doesn't apply it.

#### Set a configuration as the boot default
```bash
nixos-rebuild boot --flake ".#misc"
```

This will set the configuration as the default boot option, which will be applied after the next reboot.

#### Switch to a new configuration
```bash
nixos-rebuild switch --flake ".#misc"
```

This will build and permanently switch to the "misc" host configuration.

## Available Hosts

The available host configurations are defined in the flake.nix file and correspond to the directories under `/etc/nixos/hosts/`.

Current hosts:
- misc
- jellyimmich

## Troubleshooting

If you encounter issues with a new configuration:

1. You can boot into a previous generation from the boot menu
2. If using `test`, simply reboot to revert to the previous configuration
3. Check build logs for errors in `/tmp/nix-build-*.log` files