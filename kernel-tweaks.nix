{ config, lib, pkgs, ... }:

{
  # Disable NMI watchdog to prevent boot hangs
  boot.kernelParams = [ "nmi_watchdog=0" ];
}