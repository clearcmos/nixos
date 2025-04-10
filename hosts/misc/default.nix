# Entry point for misc host
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    # Import the hardware configuration
    ./hardware-configuration.nix
    # Import the main configuration for this host
    ./configuration.nix
    # Import shared modules
    ../../common
    ../../modules/users.nix
    ../../modules/git.nix
    ../../modules/cifs-mounts.nix
    # Import container configurations if needed
    # Add or remove container imports based on needs for this host
  ];
}