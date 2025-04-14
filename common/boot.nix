# Common boot configuration for all hosts
{ config, lib, pkgs, ... }:

{
  boot = {
    # Use the systemd-boot EFI boot loader
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    # Support for mounting CIFS/SMB and NFS shares
    supportedFilesystems = [ "cifs" "nfs" ];
    
    # Kernel sysctl parameters
    kernel.sysctl = {
      # Required for Redis to function properly
      "vm.overcommit_memory" = 1;
    };
  };
}