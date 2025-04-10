# Host-specific configuration for misc
{ config, lib, pkgs, ... }:

let
  # Helper function to load environment variables from .env file
  loadEnvFile = file:
    let
      content = builtins.readFile file;
      # Handle empty content case
      lines = if content == "" then [] else 
              builtins.filter (l: l != "" && builtins.substring 0 1 l != "#")
                             (lib.splitString "\n" content);
      parseLine = l:
        let
          parts = lib.splitString "=" l;
          key = builtins.head parts;
          value = builtins.concatStringsSep "=" (builtins.tail parts);
        in { name = key; value = value; };
      envVars = builtins.listToAttrs (map parseLine lines);
    in envVars;

  # Attempt to load the .env file, or use empty set if it doesn't exist
  envFile = "/etc/nixos/hosts/misc/.env";
  envExists = builtins.pathExists envFile;
  env = if envExists then loadEnvFile envFile else {};

  # Function to get a value from the env file with a default
  getEnv = name: default: if builtins.hasAttr name env
                         then env.${name}
                         else default;
                         
  # Get network configuration from environment variables
  hostIP = getEnv "HOST_IP" "192.168.1.3";
  hostName = getEnv "HOST_NAME" "misc";
  gatewayIP = getEnv "GATEWAY_IP" "192.168.1.1";
  dnsServers = lib.splitString " " (getEnv "DNS_SERVERS" "192.168.1.1");
  containerDataDir = getEnv "CONTAINER_DATA_DIR" "/var/lib/containers";
in
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
    hostName = hostName;
    domain = "home.arpa";
    
    # Network configuration using environment variables
    interfaces.enp3s0f0 = {
      useDHCP = false;
      ipv4.addresses = [
        { address = hostIP; prefixLength = 24; }
      ];
    };
    defaultGateway = gatewayIP;
    nameservers = dnsServers;

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

  # Make environment variables available to other modules if needed
  environment.variables = {
    HOST_IP = hostIP;
    HOST_NAME = hostName;
    GATEWAY_IP = gatewayIP;
    CONTAINER_DATA_DIR = containerDataDir;
  };

  # Example usage of environment variables in a systemd service
  systemd.services.example-service = {
    description = "Example service using environment variables";
    enable = false; # Set to true when you actually need this service
    serviceConfig = {
      # Use EnvironmentFile to load all variables
      EnvironmentFile = [
        "/etc/nixos/hosts/misc/.env"
      ];
      # Or inject specific variables directly
      Environment = [
        "HOST_IP=${hostIP}"
        "CONTAINER_DATA_DIR=${containerDataDir}"
      ];
    };
  };
}