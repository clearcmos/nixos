#!/usr/bin/env bash

# Exit on error
set -e

# Show help if needed
if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ -z "$1" ]; then
  echo "Usage: $0 <host> [action]"
  echo "Available hosts:"
  find /etc/nixos/hosts -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort
  echo ""
  echo "Available actions (default is build):"
  echo "  build     - Build the configuration without activating it"
  echo "  test      - Build and activate the configuration temporarily (reboot to revert)"
  echo "  dry-run   - Show what would be installed/changed without making changes"
  echo "  boot      - Build the configuration and set it as default boot option"
  exit 1
fi

HOST="$1"
ACTION="${2:-build}"  # Default to 'build' if no action specified

# Check if host exists
if [ ! -d "/etc/nixos/hosts/$HOST" ]; then
  echo "Error: Host '$HOST' not found in /etc/nixos/hosts/"
  echo "Available hosts:"
  find /etc/nixos/hosts -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort
  exit 1
fi

# Check if action is valid
case "$ACTION" in
  build|test|dry-run|boot)
    # valid action
    ;;
  *)
    echo "Error: Invalid action '$ACTION'"
    echo "Available actions:"
    echo "  build     - Build the configuration without activating it"
    echo "  test      - Build and activate the configuration temporarily (reboot to revert)"
    echo "  dry-run   - Show what would be installed/changed without making changes"
    echo "  boot      - Build the configuration and set it as default boot option"
    exit 1
    ;;
esac

echo "Performing '$ACTION' for host: $HOST"

# Enable flakes if they are not already enabled
if ! grep -q "experimental-features.*nix-command" /etc/nix/nix.conf && ! grep -q "experimental-features.*flakes" /etc/nix/nix.conf; then
  echo "Enabling flakes in nix configuration..."
  echo 'experimental-features = nix-command flakes' | sudo tee -a /etc/nix/nix.conf
fi

# Build the system configuration
cd /etc/nixos

case "$ACTION" in
  build)
    sudo nixos-rebuild build --flake ".#$HOST"
    echo "Build complete. To switch to this configuration, run: ./scripts/switch.sh $HOST"
    ;;
  test)
    sudo nixos-rebuild test --flake ".#$HOST"
    echo "Test complete. System is temporarily running the $HOST configuration. Reboot to revert."
    ;;
  dry-run)
    sudo nixos-rebuild dry-run --flake ".#$HOST"
    echo "Dry run complete. No changes were made to the system."
    ;;
  boot)
    sudo nixos-rebuild boot --flake ".#$HOST"
    echo "Boot configuration updated. System will boot into the $HOST configuration after restart."
    ;;
esac