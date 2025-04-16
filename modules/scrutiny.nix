# Scrutiny - Hard drive monitoring solution
{ config, lib, pkgs, ... }:

{
  # Install scrutiny package
  environment.systemPackages = with pkgs; [
    scrutiny
  ];

  # You can add more scrutiny-specific configuration here if needed
  # For example, if scrutiny has a service component:
  /*
  services.scrutiny = {
    enable = true;
    # Additional configuration options would go here
  };
  */
}