{ config, lib, pkgs, ... }:

{
  # Enable Scrutiny SMART disk monitoring
  services.scrutiny = {
    enable = true;
    openFirewall = true;  # Open the firewall for the Scrutiny web interface
    package = pkgs.scrutiny;
    
    # Enable the collector
    collector.enable = true;
  };

  # Add NGINX virtual host for Scrutiny without country restriction
  services.nginx.virtualHosts."scrutiny.bedrosn.com" = {
    forceSSL = true;
    # Fix to prevent webroot injection
    enableACME = true;
    acmeRoot = null;
    
    locations."/" = {
      proxyPass = "http://127.0.0.1:8080";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
      '';
    };
  };
}