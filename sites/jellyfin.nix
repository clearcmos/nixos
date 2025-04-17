# Jellyfin media server proxy configuration
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
in
{
  # Virtual host configuration for Jellyfin
  services.nginx.virtualHosts."jellyfin.${lib.removeSuffix "." cloudflare_domain}" = {
    forceSSL = true;
    enableACME = true;
    locations = {
      "/" = {
        # Using domain name approach instead of IP address
        proxyPass = "http://jellyimmich.home.arpa:8096";
        proxyWebsockets = true;
      };
    };
    extraConfig = ''
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      
      # Jellyfin-specific settings
      proxy_buffering off;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
      
      # Increased timeouts for streaming content
      proxy_read_timeout 600s;
      proxy_send_timeout 600s;
      
      # Allow large uploads
      client_max_body_size 0;
      
      # Disable compression for video content
      proxy_set_header Accept-Encoding "";
    '';
  };
}