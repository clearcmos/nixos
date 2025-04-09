#!/usr/bin/env bash

# Exit on error
set -e

# Show help if needed
if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ -z "$1" ]; then
  echo "Usage: $0 <host>"
  echo "Available hosts:"
  find /etc/nixos/hosts -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort
  exit 1
fi

HOST="$1"

# Check if host exists
if [ ! -d "/etc/nixos/hosts/$HOST" ]; then
  echo "Error: Host '$HOST' not found in /etc/nixos/hosts/"
  echo "Available hosts:"
  find /etc/nixos/hosts -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort
  exit 1
fi

echo "Building configuration for host: $HOST"

# Enable flakes if they are not already enabled
if ! grep -q "experimental-features.*nix-command" /etc/nix/nix.conf && ! grep -q "experimental-features.*flakes" /etc/nix/nix.conf; then
  echo "Enabling flakes in nix configuration..."
  echo 'experimental-features = nix-command flakes' | sudo tee -a /etc/nix/nix.conf
fi

# Build the system configuration
cd /etc/nixos
sudo nixos-rebuild build --flake ".#$HOST"

echo "Build complete. To switch to this configuration, run: ./scripts/switch.sh $HOST"