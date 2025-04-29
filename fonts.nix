# Enhanced font configuration for Windows 11-like font rendering in NixOS KDE
{ config, pkgs, ... }:

let
  nerdfonts = pkgs.nerdfonts;
in

{
  fonts = {
    # Enable default font packages
    enableDefaultPackages = true;
    fontDir.enable = true;
    
    # Enable GhostScript fonts
    enableGhostscriptFonts = true;
    
    fontconfig = {
      enable = true;
      
      # Add extra directory for Windows fonts
      includeUserConf = true;
      
      # Anti-aliasing configuration
      antialias = true;
      
      # Hinting configuration (slight is most similar to Windows)
      hinting = {
        enable = true;
        style = "slight";
      };
      
      # Subpixel rendering (Windows uses RGB)
      subpixel = {
        rgba = "rgb";
        lcdfilter = "default";
      };
      
      # KDE-aligned fontconfig settings based on kdeglobals
      defaultFonts = {
        serif = [ "Segoe UI" "Times New Roman" "Noto Serif" ];
        sansSerif = [ "Segoe UI" "Arial" "Noto Sans" ];
        monospace = [ "Cascadia Code" "Consolas" "Fira Code" ];
        emoji = [ "Segoe UI Emoji" "Noto Color Emoji" ];
      };
      
      # Improve rendering quality and explicitly load fonts from /fonts directory
      localConf = ''
        <?xml version="1.0"?>
        <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
        <fontconfig>
          <!-- Add Windows fonts directory -->
          <dir>/etc/nixos/fonts</dir>
          
          <!-- Improve LCD filter -->
          <match target="font">
            <edit mode="assign" name="lcdfilter">
              <const>lcddefault</const>
            </edit>
          </match>
          
          <!-- Disable autohinter for TrueType fonts -->
          <match target="font">
            <test name="fontformat" compare="eq">
              <string>TrueType</string>
            </test>
            <edit name="autohint" mode="assign">
              <bool>false</bool>
            </edit>
          </match>
          
          <!-- Enable embedded bitmaps for Asian fonts -->
          <match target="font">
            <test name="lang" compare="contains">
              <string>ja</string>
            </test>
            <edit name="embeddedbitmap" mode="assign">
              <bool>true</bool>
            </edit>
          </match>
        </fontconfig>
      '';
    };

    # Font packages - including Windows 11 equivalents and core Microsoft fonts
    packages = with pkgs; [
      # Microsoft core fonts and Windows 11 fonts
      corefonts  # Includes Arial, Times New Roman, etc.
      vistafonts  # Includes Calibri, Cambria, Consolas, etc.
      
      # Modern alternatives and supporting fonts
      cascadia-code  # Modern monospace font used in Windows Terminal
      inter  # Modern UI font similar to Segoe UI
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-emoji
      liberation_ttf  # Liberty/Open alternatives to Microsoft fonts
      dejavu_fonts
      
      # Programming fonts
      fira-code
      fira-code-symbols
      (nerdfonts.override { fonts = [ "FiraCode" "CascadiaCode" ]; })
      
      # Extra fonts for better compatibility
      ubuntu_font_family
      open-sans
      roboto
    ];
  };

  # Environment variables for better font rendering
  environment.variables = {
    # Set FreeType properties for improved rendering (Windows-like)
    FREETYPE_PROPERTIES = "truetype:interpreter-version=40";
  };
  
  # Additional packages needed for font management
  environment.systemPackages = with pkgs; [
    fontconfig  # Font configuration utilities
    freetype    # Font rendering library
    cabextract  # Needed for extracting Microsoft fonts
    fontforge   # Font editing tool (optional)
    gucharmap  # Character map to browse fonts (optional)
  ];
  
  # KDE-specific font settings
  services.desktopManager.plasma6.enable = true;  # Ensure plasma6 is enabled
  services.displayManager.defaultSession = "plasma";
  services.displayManager.sddm.settings = {
    Theme = {
      Font = "Segoe UI,10,-1,5,50,0,0,0,0,0";
    };
  };
  
  # Create a consistent KDE font experience for Nicholas user
  system.userActivationScripts.kdefonts = {
    text = ''
      echo "Setting up KDE font preferences for user nicholas"
      # Create needed directories
      mkdir -p /home/nicholas/.config
      
      # Use kwriteconfig5 to set KDE font settings
      if command -v kwriteconfig5 >/dev/null 2>&1; then
        # Set default font configuration for KDE
        kwriteconfig5 --file /home/nicholas/.config/kdeglobals --group General --key font "Segoe UI,10,-1,5,50,0,0,0,0,0"
        kwriteconfig5 --file /home/nicholas/.config/kdeglobals --group General --key fixed "Cascadia Code,10,-1,5,50,0,0,0,0,0"
        kwriteconfig5 --file /home/nicholas/.config/kdeglobals --group General --key menuFont "Segoe UI,10,-1,5,50,0,0,0,0,0"
        kwriteconfig5 --file /home/nicholas/.config/kdeglobals --group General --key smallestReadableFont "Segoe UI,8,-1,5,50,0,0,0,0,0"
        kwriteconfig5 --file /home/nicholas/.config/kdeglobals --group General --key toolBarFont "Segoe UI,10,-1,5,50,0,0,0,0,0"
        kwriteconfig5 --file /home/nicholas/.config/kdeglobals --group WM --key activeFont "Segoe UI,10,-1,5,50,0,0,0,0,0"
        
        # Force font DPI
        kwriteconfig5 --file /home/nicholas/.config/kdeglobals --group General --key forceFontDPI 96
        
        # Set font antialiasing
        kwriteconfig5 --file /home/nicholas/.config/kdeglobals --group General --key XftAntialias true
        kwriteconfig5 --file /home/nicholas/.config/kdeglobals --group General --key XftHintStyle "hintslight"
        kwriteconfig5 --file /home/nicholas/.config/kdeglobals --group General --key XftSubPixel "rgb"
      fi
      
      # Set proper permissions
      chown -R nicholas:users /home/nicholas/.config/kdeglobals 2>/dev/null || true
    '';
    deps = [];
  };
  
  # Create symlink to ensure Windows fonts are accessible
  system.activationScripts.linkWindowsFonts = {
    text = ''
      echo "Setting up Windows fonts directory access"
      
      # Fix permissions if necessary
      chmod -R +r /etc/nixos/fonts 2>/dev/null || true
      
      # Create user configuration for Nicholas to apply Windows fonts
      mkdir -p /home/nicholas/.config/fontconfig/conf.d
      cat > /home/nicholas/.config/fontconfig/conf.d/10-windows-fonts.conf << EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <!-- Add Windows fonts directory -->
  <dir>/etc/nixos/fonts</dir>
  
  <!-- Prefer Windows fonts for the default font families -->
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>Segoe UI</family>
      <family>Arial</family>
    </prefer>
  </alias>
  <alias>
    <family>serif</family>
    <prefer>
      <family>Times New Roman</family>
    </prefer>
  </alias>
  <alias>
    <family>monospace</family>
    <prefer>
      <family>Cascadia Code</family>
      <family>Consolas</family>
      <family>Fira Code</family>
    </prefer>
  </alias>
</fontconfig>
EOF
      chown -R nicholas:users /home/nicholas/.config/fontconfig
    '';
    deps = [];
  };
  
  # KDE-specific settings (these need to be set in the KDE UI, but listed here as a reminder)
  # System Settings > Appearance > Fonts
  # - Set font to Segoe UI or Inter at 10pt
  # - Force fonts DPI: 96
  # - Antialiasing: Enabled
  # - Sub-pixel rendering: RGB
  # - Hinting: Slight
}
