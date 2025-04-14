#!/usr/bin/env bash

# Exit on error
set -e

# Default to skipping image pulls for faster builds
SKIP_PULLS=true

# Show help if needed
if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ -z "$1" ]; then
  echo "Usage: $0 <host> [--pull-images]"
  echo "  --pull-images    Pull container images during rebuild (slower but ensures images are updated)"
  echo "Available hosts:"
  find /etc/nixos/hosts -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort
  exit 1
fi

HOST="$1"

# Check for --pull-images flag
if [ "$2" == "--pull-images" ]; then
  SKIP_PULLS=false
  echo "Will pull container images during rebuild (slower)"
fi

# Check if host exists
if [ ! -d "/etc/nixos/hosts/$HOST" ]; then
  echo "Error: Host '$HOST' not found in /etc/nixos/hosts/"
  echo "Available hosts:"
  find /etc/nixos/hosts -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort
  exit 1
fi

echo "Switching to configuration for host: $HOST"

# Enable flakes if they are not already enabled
if ! grep -q "experimental-features.*nix-command" /etc/nix/nix.conf && ! grep -q "experimental-features.*flakes" /etc/nix/nix.conf; then
  echo "Enabling flakes in nix configuration..."
  echo 'experimental-features = nix-command flakes' | sudo tee -a /etc/nix/nix.conf
fi

# Switch to the system configuration
cd /etc/nixos
if [ "$SKIP_PULLS" = true ]; then
  echo "Skipping container image pulls for faster rebuild..."
  SKIP_ACTIVATION_PULLS=true sudo nixos-rebuild switch --flake ".#$HOST"
else
  sudo nixos-rebuild switch --flake ".#$HOST"
fi

echo "Switch complete. System is now running the $HOST configuration."