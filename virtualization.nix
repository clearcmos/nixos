# /etc/nixos/virtualization.nix
{ config, pkgs, lib, ... }:

{
  # Enable basic virtualization support
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      ovmf.enable = true;
      swtpm.enable = true; # Enable TPM emulation
    };
  };
  
  # Add VM management tools
  environment.systemPackages = with pkgs; [
    virt-manager
    virt-viewer
    spice-gtk # For better SPICE protocol support
  ];
  
  # Add user to libvirtd group
  users.groups.libvirtd.members = [ "nicholas" ];
}