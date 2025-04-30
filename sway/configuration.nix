{ config, pkgs, lib, env, ... }:

{
  imports =
    [
      ./1password.nix
      ./aliases.nix
      ./cifs-mounts.nix
      ./claude.nix
      ./brave.nix
      ./env.nix
      ./functions.nix
      ./git.nix
      ./hardware-configuration.nix
      ./ollama.nix
      ./packages.nix
      ./ssh.nix
      ./windows.nix
      ./sway.nix
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = env.HOST_NAME;
  networking.domain = env.LAN_DOMAIN;
  
  networking.networkmanager.enable = true;
  
  networking.interfaces.enp8s0 = {
    ipv4.addresses = [
      {
        address = env.HOST_IP;
        prefixLength = 24;
      }
    ];
  };
  
  networking.nameservers = [ env.HOST_DNS ];
  networking.defaultGateway = env.HOST_ROUTER;

  time.timeZone = "America/Toronto";

  i18n.defaultLocale = "en_CA.UTF-8";

  services.xserver.enable = true;

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  services.printing.enable = true;

  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  users.users.nicholas = {
    isNormalUser = true;
    description = "Nicholas";
    extraGroups = [ "networkmanager" "wheel" "secrets" ];
    packages = with pkgs; [];
  };
  
  users.groups.secrets = {};

  programs.firefox.enable = false;

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [];
  
  programs.bash.loginShellInit = ''
    if [ "$(id -u)" -eq 0 ]; then
      cd /etc/nixos
    fi
  '';
  
  system.activationScripts.nixosPermissions = {
    text = ''
      echo "Setting up permissions for /etc/nixos"
      chown -R root:secrets /etc/nixos
      find /etc/nixos -type d -exec chmod 2770 {} \;
      find /etc/nixos -type f -exec chmod 0660 {} \;
      find /etc/nixos -name "*.sh" -type f -exec chmod +x {} \;
      chmod g+rx /etc
    '';
    deps = [];
  };
  
  programs.nix-ld.enable = true;

  programs.nano = {
    enable = true;
    nanorc = ''
      set autoindent
    '';
  };

  networking.firewall = {
    enable = false;
    allowedTCPPorts = [];
    allowedUDPPorts = [];
    extraCommands = "";
    extraStopCommands = "";
    logRefusedConnections = false;
  };

  system.stateVersion = "24.11";
}