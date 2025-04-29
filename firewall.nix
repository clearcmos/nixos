{ config, pkgs, lib, ... }:

{
  networking.firewall = {
    enable = false;
    allowedTCPPorts = [];
    allowedUDPPorts = [];
    extraCommands = "";
    extraStopCommands = "";
    logRefusedConnections = false;
  };
}
