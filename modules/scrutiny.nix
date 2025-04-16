# Scrutiny - Hard drive monitoring solution
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.scrutiny;
in
{
  options.services.scrutiny = {
    enable = mkEnableOption "Scrutiny SMART monitoring";
    
    package = mkOption {
      type = types.package;
      default = pkgs.scrutiny;
      description = "The Scrutiny package to use.";
    };
    
    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/scrutiny";
      description = "Directory to store Scrutiny data.";
    };
    
    configDir = mkOption {
      type = types.path;
      default = "/etc/scrutiny";
      description = "Directory to store Scrutiny configuration.";
    };
    
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port on which Scrutiny will listen.";
    };
  };
  
  config = mkIf cfg.enable {
    # Install scrutiny package
    environment.systemPackages = [ cfg.package ];
    
    # Create necessary directories
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 scrutiny scrutiny -"
      "d ${cfg.configDir} 0755 scrutiny scrutiny -"
    ];
    
    # Create scrutiny user and group
    users.users.scrutiny = {
      isSystemUser = true;
      group = "scrutiny";
      description = "Scrutiny SMART monitoring service user";
      home = cfg.dataDir;
    };
    
    users.groups.scrutiny = {};
    
    # Set up the systemd service
    systemd.services.scrutiny = {
      description = "Scrutiny SMART monitoring service";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      
      serviceConfig = {
        User = "scrutiny";
        Group = "scrutiny";
        ExecStart = "${cfg.package}/bin/scrutiny start";
        Restart = "on-failure";
        WorkingDirectory = cfg.dataDir;
        
        # Security settings
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [
          cfg.dataDir
          cfg.configDir
        ];
        CapabilityBoundingSet = [
          "CAP_SYS_RAWIO"  # Needed for SMART disk access
        ];
        DeviceAllow = [ "/dev/sd* r" ];
      };
      
      environment = {
        SCRUTINY_WEB_PORT = toString cfg.port;
        SCRUTINY_CONFIG = "${cfg.configDir}";
        SCRUTINY_DATABASE = "${cfg.dataDir}/scrutiny.db";
      };
    };
    
    # Set up collector service to run periodically
    systemd.services.scrutiny-collector = {
      description = "Scrutiny SMART data collector";
      
      serviceConfig = {
        Type = "oneshot";
        User = "root";  # Needs root to access disk SMART data
        ExecStart = "${cfg.package}/bin/scrutiny-collector-metrics run";
      };
    };
    
    systemd.timers.scrutiny-collector = {
      wantedBy = ["timers.target"];
      partOf = ["scrutiny-collector.service"];
      
      timerConfig = {
        OnCalendar = "hourly";
        Unit = "scrutiny-collector.service";
      };
    };
  };
}