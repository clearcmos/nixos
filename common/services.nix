# Common service configuration for all hosts
{ config, lib, pkgs, ... }:

{
  # Audio configuration (PipeWire)
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # SSH configuration
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  # File sharing services
  services.samba = {
    enable = true;
    # Additional Samba configuration would go here
  };
}