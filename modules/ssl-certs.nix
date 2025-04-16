{ config, lib, pkgs, ... }:

{
  security.acme = {
    acceptTerms = true;
    defaults = {
      # Email is already defined in nginx.nix
      webroot = "/var/lib/acme/acme-challenge";
    };
    
    certs = {
      "auth.bedrosn.com" = {
        directory = "/var/lib/acme/auth.bedrosn.com";
      };
      
      "jellyfin.bedrosn.com" = {
        directory = "/var/lib/acme/jellyfin.bedrosn.com";
      };
      
      "bedrosn.com" = {
        directory = "/var/lib/acme/bedrosn.com";
      };
      
      "diskvue.bedrosn.com" = {
        directory = "/var/lib/acme/diskvue.bedrosn.com";
      };
      
      "git.bedrosn.com" = {
        directory = "/var/lib/acme/git.bedrosn.com";
      };
      
      "overseerr.bedrosn.com" = {
        directory = "/var/lib/acme/overseerr.bedrosn.com";
      };
      
      "n8n.bedrosn.com" = {
        directory = "/var/lib/acme/n8n.bedrosn.com";
      };
      
      "ha.bedrosn.com" = {
        directory = "/var/lib/acme/ha.bedrosn.com";
      };
      
      "base.bedrosn.com" = {
        directory = "/var/lib/acme/base.bedrosn.com";
      };
      
      "cleaning.bedrosn.com" = {
        directory = "/var/lib/acme/cleaning.bedrosn.com";
      };
      
      "dash.bedrosn.com" = {
        directory = "/var/lib/acme/dash.bedrosn.com";
      };
      
      "dsm.bedrosn.com" = {
        directory = "/var/lib/acme/dsm.bedrosn.com";
      };
      
      "sab.bedrosn.com" = {
        directory = "/var/lib/acme/sab.bedrosn.com";
      };
      
      "portainer.bedrosn.com" = {
        directory = "/var/lib/acme/portainer.bedrosn.com";
      };
      
      "files.bedrosn.com" = {
        directory = "/var/lib/acme/files.bedrosn.com";
      };
      
      "radarr.bedrosn.com" = {
        directory = "/var/lib/acme/radarr.bedrosn.com";
      };
      
      "sonarr.bedrosn.com" = {
        directory = "/var/lib/acme/sonarr.bedrosn.com";
      };
      
      "photos.bedrosn.com" = {
        directory = "/var/lib/acme/photos.bedrosn.com";
      };
      
      "cockpit.bedrosn.com" = {
        directory = "/var/lib/acme/cockpit.bedrosn.com";
      };
    };
  };
}