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
  services.nginx.virtualHosts."scrutiny.bedrosn.com" = {
    # Enable HTTPS with certificate
    enableACME = false;  # Don't generate a certificate with ACME
    forceSSL = true;
    sslCertificate = "/var/lib/acme/scrutiny.bedrosn.com/fullchain.pem";
    sslCertificateKey = "/var/lib/acme/scrutiny.bedrosn.com/privkey.pem";
    
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