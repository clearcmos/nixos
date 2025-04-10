# Host-specific configuration for misc
{ config, lib, pkgs, ... }:

{
  # Enable flakes and nix-command
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  imports = [
    ../../containers/glances.nix
    ../../containers/scrutiny.nix
    ../../modules/claude.nix
    ../../modules/nginx.nix
  ];
  
  # Host-specific networking configuration with hardcoded values
  networking = {
    # Hardcoded hostname as requested
    hostName = "misc";
    domain = "home.arpa";
    
    # Hardcoded network configuration
    interfaces.enp3s0f0 = {
      useDHCP = false;
      ipv4.addresses = [
        { address = "192.168.1.3"; prefixLength = 24; }
      ];
    };
    defaultGateway = "192.168.1.1";
    nameservers = [ "192.168.1.1" ];

    firewall.enable = false;
  };

  # Add misc-specific packages
  environment.systemPackages = with pkgs; [
    cifs-utils
    compose2nix
    podman
    samba
    # Add other misc-specific packages here
  ];

  # Console configuration for CLI-only environment
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  # Environment variables that could be referenced by other modules
  environment.variables = {
    CONTAINER_DATA_DIR = "/var/lib/containers";
  };

  # Example usage of environment variables in a systemd service
  systemd.services.example-service = {
    description = "Example service using environment variables";
    enable = false; # Set to true when you actually need this service
    serviceConfig = {
      # Use EnvironmentFile to load all variables from root .env
      EnvironmentFile = [
        "/etc/nixos/.env"
      ];
      # Or inject specific variables directly
      Environment = [
        "HOST_NAME=misc"
        "HOST_IP=192.168.1.3"
        "CONTAINER_DATA_DIR=/var/lib/containers"
      ];
    };
  };
}