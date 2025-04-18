# Authentik identity management server configuration via Docker
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
  
  # Docker compose directory
  composeDir = "/etc/nixos/docker-compose/authentik";
  composeFile = "${composeDir}/docker-compose.yml";
  
  # Ensure .env file is available for docker-compose
  envFile = pkgs.writeText "authentik.env" ''
    AUTHENTIK_SECRET_KEY=${envVars.AUTHENTIK_SECRET_KEY or "changeme"}
    PG_PASS=${envVars.PG_PASS or "changeme"}
    PG_USER=authentik
    PG_DB=authentik
    AUTHENTIK_TAG=${envVars.AUTHENTIK_TAG or "2025.2.4"}
    AUTHENTIK_PORT=${envVars.AUTHENTIK_PORT or "9000"}
    # Set this to create initial admin user
    AUTHENTIK_BOOTSTRAP_PASSWORD=${envVars.BOOTSTRAP_PASSWORD or "changeme"}
    AUTHENTIK_BOOTSTRAP_EMAIL=${envVars.MAIN_EMAIL or "admin@example.com"}
    AUTHENTIK_BOOTSTRAP_TOKEN=${envVars.BOOTSTRAP_TOKEN or ""}
  '';
in
{
  # Ensure Docker is installed and running
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      log-driver = "journald";
    };
  };
  
  # Install necessary packages
  environment.systemPackages = with pkgs; [
    docker-compose
  ];
  
  # Create symlink for .env file
  systemd.tmpfiles.rules = [
    "L+ ${composeDir}/.env - - - - ${envFile}"
  ];
  
  # Create a systemd service for Authentik docker-compose
  systemd.services.authentik = {
    description = "Authentik Identity Provider (Docker)";
    wantedBy = [ "multi-user.target" ];
    after = [ "docker.service" "docker.socket" "network.target" ];
    requires = [ "docker.service" ];
    
    path = [ pkgs.docker-compose pkgs.docker ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = composeDir;
      
      # Start and stop commands for docker-compose
      ExecStartPre = [
        "${pkgs.coreutils}/bin/ln -sf ${envFile} ${composeDir}/.env"
        # Clean up old volumes if they exist
        "${pkgs.docker}/bin/docker volume rm -f docker-compose_database docker-compose_redis || true"
      ];
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose -f ${composeFile} up -d";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose -f ${composeFile} down";
      
      # Restart policy
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };

  # Virtual host configuration for Authentik
  services.nginx.virtualHosts."auth.${lib.removeSuffix "." cloudflare_domain}" = {
    forceSSL = true;
    enableACME = true;
    locations = {
      "/" = {
        proxyPass = "http://127.0.0.1:9000";
        proxyWebsockets = true;
      };
      "/ws/" = {
        proxyPass = "http://127.0.0.1:9000/ws/";
        proxyWebsockets = true;
      };
    };
    # Extra config to ensure headers are properly passed
    extraConfig = ''
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      
      # Authentik-specific settings
      proxy_buffers 8 16k;
      proxy_buffer_size 16k;
      
      # Increased timeouts for API operations
      proxy_read_timeout 300s;
      proxy_send_timeout 300s;
      
      # Allow large uploads for profile pictures, etc.
      client_max_body_size 10M;
    '';
  };
}