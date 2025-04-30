{ config, pkgs, ... }: {
  # Enable Sway as your Wayland compositor
  programs.sway.enable = true;
  programs.sway.wrapperFeatures.gtk = true;

  # Use the default Sway package from nixpkgs
  programs.sway.package = pkgs.sway;

  # Include nwg-dock in Sway's runtime environment
  programs.sway.extraPackages = with pkgs; [
    nwg-dock
    swaylock
    swayidle
    wl-clipboard
    mako
    alacritty
    dmenu
    wofi
  ];

  # Add nwg-dock to your global system packages
  environment.systemPackages = with pkgs; [
    nwg-dock
  ];

  # Set default session to Sway
  services.xserver.displayManager.defaultSession = "sway";

  # Enable xwayland for backward compatibility
  programs.sway.extraSessionCommands = ''
    export SDL_VIDEODRIVER=wayland
    export QT_QPA_PLATFORM=wayland
    export QT_WAYLAND_DISABLE_WINDOWDECORATION="1"
    export _JAVA_AWT_WM_NONREPARENTING=1
    export MOZ_ENABLE_WAYLAND=1
    
    # HiDPI environment variables
    export GDK_SCALE=1.5
    export GDK_DPI_SCALE=1
    export QT_SCALE_FACTOR=1.5
    export XCURSOR_SIZE=24
  '';

  # Configure XDG portal for screen sharing
  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = "*";
  };
  
  # Font configuration for HiDPI
  fonts = {
    enableDefaultPackages = true;
    fontconfig = {
      defaultFonts = {
        serif = [ "DejaVu Serif" ];
        sansSerif = [ "DejaVu Sans" ];
        monospace = [ "DejaVu Sans Mono" ];
      };
      # Increase DPI for fonts
      antialias = true;
      hinting.enable = true;
      hinting.style = "slight";
    };
    
    # Add fonts with good HiDPI support
    packages = with pkgs; [
      dejavu_fonts
      noto-fonts
      noto-fonts-emoji
      fira-code
      fira-code-symbols
    ];
  };
  
  # Copy Sway config file to user's config directory
  system.activationScripts.setupSwayConfig = ''
    # Create sway config directory for nicholas user
    mkdir -p /home/nicholas/.config/sway
    
    # Copy the config file
    cp -f ${./sway-config/config} /home/nicholas/.config/sway/config
    
    # Set proper ownership
    chown -R nicholas:users /home/nicholas/.config/sway
  '';
}