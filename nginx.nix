# Nginx and ACME configuration for NixOS
{ config, lib, pkgs, ... }:

let
  # Load environment variables from .env file
  loadEnv = path:
    let
      content = builtins.readFile path;
      # Split into lines and filter comments/empty lines
      lines = lib.filter (line:
        line != "" &&
        !(lib.hasPrefix "#" line)
      ) (lib.splitString "\n" content);

      # Split each line into key/value with improved handling for quotes and special chars
      parseLine = line:
        let
          # Use a more robust regex that handles quotes and spaces around equals sign
          match = builtins.match "([^=]+)=([\"']?)([^\"]*)([\"']?)" line;
          key = if match == null then null else lib.elemAt match 0;
          # Extract the value without quotes
          value = if match == null then null else lib.elemAt match 2;
        in if match == null
           then null
           else { name = lib.removeSuffix " " (lib.removePrefix " " key); value = value; };

      # Convert to attribute set, filtering out null values from parsing failures
      parsedLines = map parseLine lines;
      validLines = builtins.filter (x: x != null) parsedLines;
      env = builtins.listToAttrs validLines;
    in env;

  envVars = loadEnv "/etc/nixos/.env";
  main_email = envVars.MAIN_EMAIL;
in
{
  # Users required for nginx and ACME
  users.users = {
    # ACME needs a user for certificate operations
    acme = {
      isSystemUser = true;
      group = "acme";
      home = "/var/lib/acme";
    };

    # Nginx needs a user
    nginx = {
      isSystemUser = true;
      group = "nginx";
      home = "/var/lib/nginx";
    };
  };

  # Define the required groups
  users.groups = {
    nginx = {};
    acme = {};
  };

  # Nginx configuration
  services.nginx = {
    enable = true;

    # Recommended settings
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    # Additional SSL settings for better security and compatibility
    sslCiphers = "EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH";
    sslProtocols = "TLSv1.2 TLSv1.3";

    # The virtual hosts will be imported from the sites directory
  };

  # ACME (Let's Encrypt) configuration
  security.acme = {
    acceptTerms = true;
    defaults.email = main_email;

    # Add required user for ACME
    defaults.group = "nginx";
    defaults.webroot = "/var/lib/acme/acme-challenge";
  };

  # Ensure ports are open for HTTP/HTTPS
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # System activation scripts for ACME
  system.activationScripts = {
    debugAcmeEmail = ''
      echo "DEBUG: ACME email being used: ${main_email}" > /tmp/acme-email-debug
    '';
  };
}