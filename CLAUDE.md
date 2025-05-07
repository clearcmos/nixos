# CLAUDE INSTRUCTIONS

## Documentation Reference Policy

1. ONLY load and reference files from `/etc/nixos/docs/*.md` when specifically requested (when user broadly asks about checking docs).

2. When a user asks about a topic like "rdp" or "remote desktop", load and reference `/etc/nixos/docs/rdp.md`. This is a general idea, but should work broadly.

3. DO NOT reference files under the docs directory unless specifically asked about the topic vaguely matching filename.

4. Always run the following commands when NixOS configurations are updated:
   - `nixos-rebuild switch` for applying changes permanently, don't test unless I ask you.

5. For configuration issues, always check service status, logs, and relevant configuration files.

## Standard Troubleshooting Procedure

When troubleshooting NixOS services:

1. Check if the service is running:
   ```bash
   systemctl status <service-name>
   ```

2. View recent logs:
   ```bash
   journalctl -u <service-name> -n 50
   ```

3. Verify configuration files with appropriate tools based on the service type.

4. Test configuration changes before applying permanently:
   ```bash
   nixos-rebuild test
   ```

5. Apply working changes permanently:
   ```bash
   nixos-rebuild switch
   ```
