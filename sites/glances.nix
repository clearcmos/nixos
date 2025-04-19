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

  envVars = loadEnv "/etc/nixos/.secrets/.env";
  cloudflare_domain = envVars.CLOUDFLARE_DOMAIN;
  
  # Domain settings  
  glances_domain = "glances.${lib.removeSuffix "." cloudflare_domain}";
  authentik_domain = "auth.${lib.removeSuffix "." cloudflare_domain}";
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
  services.nginx.virtualHosts."${glances_domain}" = {
    forceSSL = true;
    enableACME = true;
    
    # Reimplement authentik authentication enforcement
    locations = {
      # Main Glances application with auth enforcement
      "/" = {
        proxyPass = "http://127.0.0.1:61208";
        proxyWebsockets = true;
        extraConfig = ''
          # Auth enforcement
          auth_request /outpost.goauthentik.io/auth/nginx;
          error_page 401 = @goauthentik_proxy_signin;
          
          # Header passing
          auth_request_set $authentik_cookie $upstream_http_set_cookie;
          add_header Set-Cookie $authentik_cookie;
          
          # User info passing
          auth_request_set $authentik_username $upstream_http_x_authentik_username;
          auth_request_set $authentik_groups $upstream_http_x_authentik_groups;
          auth_request_set $authentik_email $upstream_http_x_authentik_email;
          auth_request_set $authentik_name $upstream_http_x_authentik_name;
          
          proxy_set_header X-authentik-username $authentik_username;
          proxy_set_header X-authentik-groups $authentik_groups;
          proxy_set_header X-authentik-email $authentik_email;
          proxy_set_header X-authentik-name $authentik_name;
        '';
      };
      
      # Static files don't need auth
      "/static/" = {
        proxyPass = "http://127.0.0.1:61208/static/";
      };
      
      # Authentik endpoints
      "/outpost.goauthentik.io/" = {
        proxyPass = "http://127.0.0.1:9000/outpost.goauthentik.io/";
        extraConfig = ''
          proxy_set_header Host ${authentik_domain};
          proxy_set_header X-Original-URL $scheme://$host$request_uri;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Host $host;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        '';
      };
      
      # Named location for auth redirects
      "@goauthentik_proxy_signin" = {
        extraConfig = ''
          internal;
          add_header Set-Cookie $authentik_cookie;
          return 302 /outpost.goauthentik.io/start?rd=$scheme://$host$request_uri;
        '';
      };
    };
    
    # General proxy settings
    extraConfig = ''
      # Standard proxy headers
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      
      # Timeouts
      proxy_read_timeout 300s;
      proxy_send_timeout 300s;
    '';
  };
}