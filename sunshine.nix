{ config, pkgs, lib, ... }:

{
  # Install Sunshine and Moonlight packages
  environment.systemPackages = with pkgs; [
    moonlight-qt # For local testing
    sunshine     # System-wide installation
  ];

  # Enable the Sunshine service with proper Wayland support
  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true;       # Needed for Wayland support and some encoders
    openFirewall = true;      # Opens required ports automatically
    
    # Fix port conflicts and ensure proper systemd unit setup
    # The service will be automatically launched as a user service
    package = pkgs.sunshine;
    
    # Ensure Sunshine has a proper config
    settings = {
      # Force Sunshine to use unique ports if needed
      port = 48010;
      
      # Set default display method
      capture = "kms";
      
      # Ensure proper encoder settings for AMD GPU
      encoder = "vaapi";
    };
  };

  # Note: Firewall is completely disabled in configuration.nix
  # The following ports would normally need to be opened:
  # TCP: 47984, 47989, 47990, 48010
  # UDP: 47998-48000, 8000-8010

  # Ensure XDG desktop portal is enabled for screen sharing on Wayland
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-kde ];
    config.common.default = "*";
  };

  # Add Wayland support settings
  environment.sessionVariables = {
    # Ensure Wayland display variable is available to system services
    WAYLAND_DISPLAY = "wayland-0";
  };
  
  # Add user-specific packages for Nicholas
  users.users.nicholas.packages = with pkgs; [
    moonlight-qt
  ];
  
  # Add nicholas to input and uinput groups for virtual input devices
  users.users.nicholas.extraGroups = [ "input" "uinput" "video" "render" ];

  # Add udev rules for input permissions
  services.udev.extraRules = ''
    KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
    # Add additional permissions for KMS/DRM access
    KERNEL=="card*", SUBSYSTEM=="drm", GROUP="video", MODE="0660"
    KERNEL=="renderD*", SUBSYSTEM=="drm", GROUP="render", MODE="0660"
  '';

  # Ensure config directories exist with proper permissions
  systemd.tmpfiles.rules = [
    "d /var/lib/sunshine 0755 root root -"
    "d /var/log/sunshine 0755 root root -"
    "d /home/nicholas/.config/sunshine 0750 nicholas nicholas -"
  ];

  # Set up instruction file for connecting
  environment.etc."sunshine-instructions".text = ''
    Sunshine Remote Desktop/Game Streaming Setup:

    1. Make sure your NixOS system is running and you are logged into KDE Plasma on Wayland
    
    2. Start Sunshine manually (first time):
       - Run 'sunshine' in a terminal
       - Or run 'systemctl --user start sunshine' to start the service
    
    3. Configure Sunshine (first-time setup):
       - Access the Sunshine web interface at https://localhost:47990
       - Create a username and password
       - Configure your streams and apps (desktop should be included by default)
    
    4. From a remote device:
       - Install Moonlight client (available for Windows, macOS, Linux, Android, iOS)
       - Open Moonlight and add your NixOS machine
       - If it doesn't appear automatically, use "Add Host Manually" and enter "${config.networking.hostName}:47989" or your IP address
       - Initiate pairing and enter the PIN shown on the client into the Sunshine web UI when prompted
    
    5. Start streaming:
       - Select your NixOS host in Moonlight
       - Choose "Desktop" or any other configured app
       - Connect and enjoy your remote session
    
    Security notes:
    - Make sure required ports (47984, 47989, 47990, 48010 TCP and 47998-48000, 8000-8010 UDP) are forwarded in your router
    - Consider setting up a VPN for additional security when connecting over the internet
    
    Troubleshooting:
    - If you can't connect, verify Sunshine is running: systemctl --user status sunshine
    - For encoder errors on Wayland, ensure capSysAdmin = true is set
    - If you see "Unable to create virtual mouse/keyboard" errors, log out and back in after rebuild
    - Check the Sunshine web UI for additional settings and diagnostics
    - Check logs with: journalctl --user -u sunshine
    - If you have port conflicts, ensure no other services are using Sunshine's ports
    
    For more detailed information, visit:
    - https://nixos.wiki/wiki/Sunshine
    - https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide
  '';
}