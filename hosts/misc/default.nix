# Entry point for misc host
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    # Import the hardware configuration
    ./hardware-configuration.nix
    # Import the main configuration for this host
    ./configuration.nix
    # Import OpenVPN configuration
    ./openvpn.nix
    # Import shared modules
    ../../common
    ../../modules/users.nix
    ../../modules/git.nix
    ../../modules/cifs-mounts.nix
    # Import site configurations
    ../../sites/glances.nix
    ../../sites/scrutiny.nix
    # Container configurations are now managed through podman-containers module in configuration.nix
  ];
}