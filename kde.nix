# KDE Plasma specific configurations
{ config, pkgs, lib, ... }:

{
  # Enable the X11 windowing system
  services.xserver.enable = true;

  # Enable the KDE Plasma Desktop Environment
  services.desktopManager.plasma6 = {
    enable = true;
    # Customize additional settings as needed
  };
  
  # Enable SDDM display manager with default settings
  services.displayManager.sddm.enable = true;
  
  # Enable Bluetooth support
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # Disable sleep when inactive by setting power management systemd service
  environment.etc."xdg/autostart/disable-sleep.desktop" = {
    text = ''
      [Desktop Entry]
      Name=Disable Sleep
      Exec=bash -c "sleep 10 && qdbus org.kde.Solid.PowerManagement /org/kde/Solid/PowerManagement setPowerSaveMode 0 && qdbus org.kde.Solid.PowerManagement /org/kde/Solid/PowerManagement setScreenBrightnessChangeEnabled false"
      Type=Application
      X-KDE-AutostartPhase=Application
    '';
    mode = "0644";
  };

  # Configure KDE power management settings using systemd
  systemd.user.services.configure-powerdevil = {
    description = "Configure KDE Powerdevil settings";
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "configure-powerdevil" ''
        mkdir -p $HOME/.config
        cat > $HOME/.config/powerdevilrc << EOF
[AC][SuspendAndShutdown]
AutoSuspendAction=0
EOF
      '';
    };
  };

  # KDE-specific packages
  environment.systemPackages = with pkgs; [
    kdePackages.powerdevil # Power management
    kdePackages.kate       # Text editor
    kdePackages.bluedevil  # KDE Bluetooth integration
  ];
}