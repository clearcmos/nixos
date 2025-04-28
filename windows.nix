{ config, lib, pkgs, ... }:

let
  # Get the username from config if it exists, or fall back to "nicholas"
  regular_user = if config ? users.regularUser then config.users.regularUser else "nicholas";
  # Get uid dynamically
  uid = toString config.users.users.${regular_user}.uid;
in {
  # Ensure ntfs-3g is installed
  environment.systemPackages = with pkgs; [
    ntfs3g
  ];

  # Automatically mount NTFS partitions
  fileSystems."/mnt/windows" = {
    device = "/dev/disk/by-uuid/AA2453C524539365";
    fsType = "ntfs-3g";
    options = [ "rw" "uid=${uid}" "gid=100" "fmask=0117" "dmask=0007" "nofail" "x-systemd.automount" ];
  };
  
  # Create the mount point directory
  system.activationScripts.windowsMountPoints = ''
    mkdir -p /mnt/windows
  '';
}