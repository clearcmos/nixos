# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, env, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./1password.nix
      ./aliases.nix
      ./cifs-mounts.nix
      ./claude.nix
      ./brave.nix
      ./env.nix
      ./fonts.nix
      ./functions.nix
      ./git.nix
      ./hardware-configuration.nix
      ./ollama.nix
      ./ssh.nix
      ./windows.nix
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Define hostname and domain from .env file
  networking.hostName = env.HOST_NAME;
  networking.domain = env.LAN_DOMAIN;
  
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;
  
  # Static IP configuration from .env file
  networking.interfaces.enp8s0 = {
    ipv4.addresses = [
      {
        address = env.HOST_IP;
        prefixLength = 24; # For 255.255.255.0
      }
    ];
  };
  
  # DNS and gateway settings from .env file
  networking.nameservers = [ env.HOST_DNS ];
  networking.defaultGateway = env.HOST_ROUTER;

  # Set your time zone.
  time.timeZone = "America/Toronto";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_CA.UTF-8";

  # Enable the X11 windowing system.
  # You can disable this if you're only using the Wayland session.
  services.xserver.enable = true;

  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.nicholas = {
    isNormalUser = true;
    description = "Nicholas";
    extraGroups = [ "networkmanager" "wheel" "secrets" ];
    packages = with pkgs; [
      kdePackages.kate
    #  thunderbird
    ];
  };
  
  # Create the secrets group
  users.groups.secrets = {};

  # Install firefox.
  programs.firefox.enable = false;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
  #  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #  wget
  ];
  
  # Configure root shell to start in /etc/nixos directory when logging in
  programs.bash.loginShellInit = ''
    if [ "$(id -u)" -eq 0 ]; then
      cd /etc/nixos
    fi
  '';

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };
  
  # Set permissions on /etc/nixos so the secrets group has full control
  system.activationScripts.nixosPermissions = {
    text = ''
      echo "Setting up permissions for /etc/nixos"
      chown -R root:secrets /etc/nixos
      # Ensure directories have appropriate permissions with execute bit for group
      find /etc/nixos -type d -exec chmod 2770 {} \;
      # Set permission for files
      find /etc/nixos -type f -exec chmod 0660 {} \;
      # Make all scripts executable
      find /etc/nixos -name "*.sh" -type f -exec chmod +x {} \;
      # Ensure parent directories are accessible
      chmod g+rx /etc
    '';
    deps = [];
  };
  
  # Enable nix-ld
  programs.nix-ld.enable = true;

  # List services that you want to enable:

  # OpenSSH configuration moved to ssh.nix

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?

}
