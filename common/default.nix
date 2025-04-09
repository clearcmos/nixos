# Common configurations shared between all hosts
{ config, lib, pkgs, ... }:

{
  imports = [
    ./boot.nix
    ./network.nix
    ./services.nix
    ./aliases.nix
  ];

  # Common packages for all hosts
  environment.systemPackages = with pkgs; [
    cacert
    curl
    fzf
    git
    gnupg
    htop
    jq
    ncdu
    nmap
    nodejs
    pkg-config
    python3
    rsync
    sudo
    tldr
    wget
  ];

  # Common settings for all hosts
  nixpkgs.config.allowUnfree = true;
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  
  # Enable nix-ld for better compatibility with non-NixOS binaries
  programs.nix-ld.enable = true;

  # Automatic system updates
  system.autoUpgrade = {
    enable = true;
    allowReboot = false;
    dates = "04:00";
    randomizedDelaySec = "45min";
    persistent = true;
  };

  # This value determines the NixOS release
  system.stateVersion = "24.11";
}