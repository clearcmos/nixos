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

  # Configure certificate for Scrutiny
  security.acme.certs."scrutiny.bedrosn.com" = {
    directory = "/var/lib/acme/scrutiny.bedrosn.com";
  };

  # Add NGINX virtual host for Scrutiny with country restriction
  services.nginx.virtualHosts."scrutiny.bedrosn.com" = {
    # Enable HTTPS with certificate
    forceSSL = true;
    useACMEHost = "scrutiny.bedrosn.com";
    
    locations."/" = {
      proxyPass = "http://localhost:8080";
      proxyWebsockets = true;
      extraConfig = ''
        # Block countries not in the whitelist
        if ($allowed_country = no) {
          return 403;
        }
        
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
      '';
    };
  };
}