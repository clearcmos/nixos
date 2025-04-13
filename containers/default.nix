# Default imports for containers directory
# This file allows importing the entire directory as a module

{ config, lib, pkgs, ... }:

{
  # Import all container configurations
  imports = [
    ./authentik.nix
    ./glances.nix
    ./radarr.nix
    ./sabnzbd.nix
    ./scrutiny.nix
    ./sonarr.nix
    # Add any other container configurations here
  ];
}