{ config, lib, pkgs, ... }:

{
  # Install Brave browser
  environment.systemPackages = with pkgs; [
    brave
  ];

  # Set Brave as default browser
  xdg.mime.defaultApplications = {
    "x-scheme-handler/http" = "brave-browser.desktop";
    "x-scheme-handler/https" = "brave-browser.desktop";
    "text/html" = "brave-browser.desktop";
    "application/xhtml+xml" = "brave-browser.desktop";
    "application/pdf" = "brave-browser.desktop";
  };

  # Brave-specific policy settings
  # These will apply to Brave specifically through a policies.json file
  environment.etc."brave/policies/managed/policies.json" = {
    text = builtins.toJSON {
      BrowserSignin = 0;
      SyncDisabled = true;
      PasswordManagerEnabled = false;
      AutofillAddressEnabled = false;
      AutofillCreditCardEnabled = false;
      DefaultBrowserSettingEnabled = true;
      MetricsReportingEnabled = false;
      SearchSuggestEnabled = false;
      SpellcheckEnabled = true;
      SpellcheckLanguage = [
        "en-US"
        "en-CA"
        "fr"
      ];
      RestoreOnStartup = 1;
      
      # Default search engine
      DefaultSearchProviderEnabled = true;
      DefaultSearchProviderName = "Google";
      DefaultSearchProviderSearchURL = "https://www.google.com/search?q={searchTerms}";
      DefaultSearchProviderSuggestURL = "https://www.google.com/complete/search?output=chrome&q={searchTerms}";
      DefaultSearchProviderIconURL = "https://www.google.com/favicon.ico";
      DefaultSearchProviderKeyword = "google";
      
      # Brave-specific settings
      BraveRewardsDisabled = true;
      BraveTodayDisabled = true;
      BraveAdblockEnabled = true;
      
      # Extensions - use the same ones as in your Chromium config
      ExtensionSettings = {
        "aeblfdkhhhdcdjpifhhbdiojplfjncoa" = {
          installation_mode = "normal_installed";
          update_url = "https://clients2.google.com/service/update2/crx";
        };
        "cjpalhdlnbpafiamejdnhcphjbkeiagm" = {
          installation_mode = "normal_installed";
          update_url = "https://clients2.google.com/service/update2/crx";
        };
        "jcokdfogijmigonkhckmhldgofjmfdak" = {
          installation_mode = "normal_installed";
          update_url = "https://clients2.google.com/service/update2/crx";
        };
        "mmpokgfcmbkfdeibafoafkiijdbfblfg" = {
          installation_mode = "normal_installed";
          update_url = "https://clients2.google.com/service/update2/crx";
        };
      };
    };
    mode = "0644";
  };

  # Environment variables for Brave
  environment.variables = {
    BRAVE_ENABLE_WAYLAND = "1"; # For Wayland support
    NIXOS_OZONE_WL = "1";       # Needed for Ozone/Wayland
  };
}
