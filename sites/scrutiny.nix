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

  # Add NGINX virtual host for Scrutiny with country restriction
  services.nginx.virtualHosts."scrutiny.${config.networking.hostName}.${config.networking.domain}" = {
    # Enable HTTPS with imported certificate
    forceSSL = true;
    useACMEHost = "scrutiny.${config.networking.hostName}.${config.networking.domain}";
    
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
  
  # Configure imported certificate
  security.acme.certs."scrutiny.${config.networking.hostName}.${config.networking.domain}" = {
    # Mark certificate as external (imported) to prevent automatic renewal attempts
    # until you're ready to switch to NixOS-managed renewal
    directory = "/var/lib/acme/scrutiny.${config.networking.hostName}.${config.networking.domain}";
  };
}