# Common network configuration for all hosts
{ config, lib, pkgs, ... }:

{
  networking = {
    # Default domain for all hosts
    domain = "home.arpa";
    
    # Default firewall configuration
    firewall.enable = false;
  };
}