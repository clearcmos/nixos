# NixOS Configuration Management

This document explains how to build, test, and deploy NixOS configurations for different hosts using the provided scripts. This system uses the Nix Flakes feature, so flakes must be enabled for these scripts to work.

## Available Scripts

The repository includes two main scripts for working with NixOS configurations:

- **build.sh**: For building and testing configurations without permanently switching
- **switch.sh**: For switching permanently to a new configuration

These scripts are located in the `/etc/nixos/scripts/` directory.

## Building and Testing Configurations

The `build.sh` script allows you to build, test, or perform a dry run of a configuration without permanently switching to it.

### Usage

```bash
/etc/nixos/scripts/build.sh <host> [action]
```

Where:
- `<host>` is the name of the host configuration to use (matches a directory under `/etc/nixos/hosts/`)
- `[action]` is optional and can be one of:
  - `build` (default): Build the configuration without activating it
  - `test`: Build and activate the configuration temporarily (reboot to revert)
  - `dry-run`: Show what would be installed/changed without making changes
  - `boot`: Build the configuration and set it as default boot option

### Examples

#### Perform a dry run for the "misc" host
```bash
/etc/nixos/scripts/build.sh misc dry-run
```

This will show what would be installed or changed without actually making any changes.

#### Test a configuration temporarily
```bash
/etc/nixos/scripts/build.sh misc test
```

This will build and activate the configuration for the "misc" host temporarily. The changes will be reverted upon reboot.

#### Build a configuration without activating it
```bash
/etc/nixos/scripts/build.sh misc
# or
/etc/nixos/scripts/build.sh misc build
```

This builds the configuration but doesn't apply it.

#### Set a configuration as the boot default
```bash
/etc/nixos/scripts/build.sh misc boot
```

This will set the configuration as the default boot option, which will be applied after the next reboot.

## Switching to a New Configuration

The `switch.sh` script allows you to permanently switch to a new configuration.

### Usage

```bash
/etc/nixos/scripts/switch.sh <host>
```

Where:
- `<host>` is the name of the host configuration to use (matches a directory under `/etc/nixos/hosts/`)

### Example

```bash
/etc/nixos/scripts/switch.sh misc
```

This will build and permanently switch to the "misc" host configuration.

## Available Hosts

To see a list of available host configurations, you can run either script without arguments or with the `-h` or `--help` flag:

```bash
/etc/nixos/scripts/build.sh
# or
/etc/nixos/scripts/switch.sh
```

## Workflow Recommendations

1. **Always start with a dry run**: Before making any changes, use the `dry-run` action to see what would change.
   ```bash
   /etc/nixos/scripts/build.sh <host> dry-run
   ```

2. **Test changes temporarily**: If the dry run looks good, test the changes temporarily before committing.
   ```bash
   /etc/nixos/scripts/build.sh <host> test
   ```

3. **Switch permanently**: Only after confirming the test configuration works as expected, switch to it permanently.
   ```bash
   /etc/nixos/scripts/switch.sh <host>
   ```

4. **Prepare boot config for critical changes**: For changes that might affect system stability, use the `boot` action and reboot to apply.
   ```bash
   /etc/nixos/scripts/build.sh <host> boot
   # Then reboot
   ```

## Troubleshooting

If you encounter issues with a new configuration:

1. You can boot into a previous generation from the boot menu
2. If using `test`, simply reboot to revert to the previous configuration
3. Check build logs for errors in `/tmp/nix-build-*.log` files