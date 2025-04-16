# Host-specific configuration for jellyimmich
{ config, lib, pkgs, ... }:

{
  # Enable flakes and nix-command
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  
  # Host-specific networking configuration with hardcoded values
  networking = {
    # Hardcoded hostname as requested
    hostName = "jellyimmich";
    domain = "home.arpa";
    
    # Hardcoded network configuration
    interfaces.enp3s0f0 = {
      useDHCP = false;
      ipv4.addresses = [
        { address = "192.168.1.200"; prefixLength = 24; }
      ];
    };
    defaultGateway = "192.168.1.1";
    nameservers = [ "192.168.1.1" ];

    firewall.enable = false;
  };

  # Host-specific packages
  environment.systemPackages = with pkgs; [
    # Add jellyimmich-specific packages here
    cifs-utils
    samba
  ];

  # Any other jellyimmich-specific configurations
  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };
  
  services.immich = {
    enable = true;
    # Add immich-specific configurations as needed
  };
  
  # Environment variables that could be referenced by other modules
  environment.variables = {
  };
  
  # Example usage of environment variables in a systemd service
  systemd.services.example-service = {
    description = "Example service using environment variables";
    enable = false; # Set to true when you actually need this service
    serviceConfig = {
      # Use EnvironmentFile to load all variables
      EnvironmentFile = [
        "/etc/nixos/.env"
      ];
      # Or inject specific variables directly
      Environment = [
        "HOST_NAME=jellyimmich"
        "HOST_IP=192.168.1.200"
      ];
    };
  };
}