# Module for setting up Podman containers directly from docker-compose.yml files
{ config, lib, pkgs, ... }:

{
  imports = [
    # Import the podman-compose module
    ../containers/podman-compose.nix
  ];
  
  # Enable podman-compose services
  services.podman-compose.enable = true;
  
  # Additional podman configuration
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };
  
  # Add useful container management tools
  environment.systemPackages = with pkgs; [
    podman
    podman-compose
    podman-tui
    
    # Additional dependencies required for our scripts
    gnused
    gawk
    gettext # For envsubst
  ];
  
  # Create a convenient shell alias to list container services
  programs.bash.shellAliases = {
    plist = "systemctl list-units 'podman-compose-*' | grep -v 'loaded units'";
    pstatus = "systemctl status podman-compose-*";
    prestart = "sudo systemctl restart podman-compose-";
  };
}