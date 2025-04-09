# Host-specific configuration for jellyimmich
{ config, lib, pkgs, ... }:

{
  # Host-specific networking configuration
  networking = {
    hostName = "jellyimmich";
    
    # Network configuration - adjust as needed for jellyimmich
    interfaces.enp3s0f0 = {
      useDHCP = false;
      ipv4.addresses = [
        { address = "192.168.1.10"; prefixLength = 24; }
      ];
    };
    defaultGateway = "192.168.1.1";
    nameservers = [ "192.168.1.1" ];
  };

  # Host-specific packages
  environment.systemPackages = with pkgs; [
    # Add jellyimmich-specific packages here
    podman
    compose2nix
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
}