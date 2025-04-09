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
  
  # Host-specific networking configuration
  networking = {
    hostName = "misc";
    domain = "home.arpa";
    
    # Network configuration
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

  # Any other host-specific configurations
  services.xserver = {
    enable = true;
    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;
  };

  # ENVIRONMENT VARIABLES USAGE
  #
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
      Environment = let
        getEnv = name: default: if builtins.hasAttr name config.environment.variables
                               then config.environment.variables.${name}
                               else default;
      in [
        "API_KEY=${getEnv "API_KEY" "default-placeholder-value"}"
      ];
    };
  };
}