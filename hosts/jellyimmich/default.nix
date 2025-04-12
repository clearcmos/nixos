# Entry point for jellyimmich host
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
    ../../modules/claude.nix
    ../../modules/git.nix
    ../../modules/nginx.nix
    # Import container configurations if needed
    ../../containers/glances.nix
    ../../containers/scrutiny.nix
  ];
}