# Git configuration for NixOS
{ config, pkgs, ... }:

{
  # Install Git package
  environment.systemPackages = with pkgs; [
    git
  ];

  # Configure global Git settings
  programs.git = {
    enable = true;
    config = {
      init.defaultBranch = "main";
      user = {
        email = "whatever@domain.com";
        name = "clearcmos";
      };
    };
  };

  # Add the pushnix function to push NixOS configuration changes
  programs.bash.shellAliases = {
    pushnix = "cd /etc/nixos && git add . && git commit -m \"Updates\" && git push";
  };
}