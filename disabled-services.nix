# This file defines services that should always be disabled
{ config, lib, ... }:

{
  # Disable wpa_supplicant service since we're using NetworkManager
  systemd.services.wpa_supplicant.enable = lib.mkForce false;
  
  # Disable ModemManager service
  systemd.services.ModemManager.enable = lib.mkForce false;
}