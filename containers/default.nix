# Containers directory default module
# This file allows importing the entire directory
{ config, lib, pkgs, ... }:

{
  # This is now an empty import because containers are managed
  # via podman-compose.nix and the YAML files directly
}