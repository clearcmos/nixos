{ config, lib, pkgs, ... }:

{
  # Add NGINX virtual host for Glances with country restriction
  services.nginx.virtualHosts."glances.bedrosn.com" = {
    # Enable HTTPS with certificate
    enableACME = false;  # Don't generate a certificate with ACME
    forceSSL = true;
    sslCertificate = "/var/lib/acme/glances.bedrosn.com/fullchain.pem";
    sslCertificateKey = "/var/lib/acme/glances.bedrosn.com/privkey.pem";
    
    locations."/" = {
      proxyPass = "http://localhost:61208";
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
  
  # Enable Glances as a web service
  systemd.services.glances = {
    description = "Glances system monitoring web service";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.glances}/bin/glances -w -t 5 --port 61208 -B 0.0.0.0";
      Restart = "always";
      RestartSec = 3;
      User = "root";  # Running as root to access all system info
    };
  };
}