{ config, lib, pkgs, ... }:

{
  # Add NGINX virtual host for Glances without country restriction
  services.nginx.virtualHosts."glances.bedrosn.com" = {
    forceSSL = true;
    # Fix to prevent webroot injection
    enableACME = true;
    acmeRoot = null;
    
    locations."/" = {
      proxyPass = "http://127.0.0.1:61208";
      proxyWebsockets = true;
      extraConfig = ''
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