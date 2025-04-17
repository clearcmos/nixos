# Glances system monitoring service configuration
{ config, lib, pkgs, ... }:

let
  # Load environment variables from .env file
  loadEnv = path:
    let
      content = builtins.readFile path;
      lines = lib.filter (line:
        line != "" &&
        !(lib.hasPrefix "#" line)
      ) (lib.splitString "\n" content);

      parseLine = line:
        let
          match = builtins.match "([^=]+)=([\"']?)([^\"]*)([\"']?)" line;
          key = if match == null then null else lib.elemAt match 0;
          value = if match == null then null else lib.elemAt match 2;
        in if match == null
           then null
           else { name = lib.removeSuffix " " (lib.removePrefix " " key); value = value; };

      parsedLines = map parseLine lines;
      validLines = builtins.filter (x: x != null) parsedLines;
      env = builtins.listToAttrs validLines;
    in env;

  envVars = loadEnv "/etc/nixos/.env";
  cloudflare_domain = envVars.CLOUDFLARE_DOMAIN;
  basic_username = envVars.BASIC_USERNAME;
  basic_password = envVars.BASIC_PASSWORD;
in
{
  # Ensure the required package is installed
  environment.systemPackages = with pkgs; [
    glances
  ];

  # Glances service configuration
  services.glances = {
    enable = true;
    port = 61208;
    extraArgs = [
      "--webserver"
      "--bind=127.0.0.1"
    ];
  };

  # Virtual host configuration for Glances
  services.nginx.virtualHosts."glances.${lib.removeSuffix "." cloudflare_domain}" = {
    forceSSL = true;
    enableACME = true;
    # Add basic authentication
    basicAuthFile = pkgs.writeText "glances.htpasswd" ''
      ${basic_username}:{PLAIN}${basic_password}
    '';
    locations = {
      "/" = {
        proxyPass = "http://localhost:61208";
        proxyWebsockets = true;
      };
      "/static/" = {
        proxyPass = "http://localhost:61208/static/";
      };
      "/api" = {
        proxyPass = "http://localhost:61208/api";
        proxyWebsockets = true;
      };
    };
    extraConfig = ''
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_read_timeout 300s;
      proxy_send_timeout 300s;
    '';
  };
}