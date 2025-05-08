# /etc/nixos/windows.nix
{ config, pkgs, lib, ... }:

let
  # Discover your iGPU’s PCI vendor:device with:
  #    lspci -nn | grep '00:02.0'
  igpuVendorDevice = "8086:0410";  # ← replace this with your actual ID

in {
  # 1) Enable VT-d/IOMMU and bind the Intel iGPU to VFIO
  boot.kernelParams = [
    "intel_iommu=on"
    "iommu=pt"
    "vfio-pci.ids=${igpuVendorDevice}"
  ];
  boot.blacklistedKernelModules = [ "i915" ];

  # 2) Load VFIO modules early
  boot.initrd.kernelModules = [
    "vfio"
    "vfio_pci"
    "vfio_iommu_type1"
    "vfio_virqfd"
  ];

  # 3) Enable KVM
  boot.kernelModules = [
    pkgs.kmod.kvm_intel
    "kvm"
  ];

  # 4) QEMU + libvirtd
  virtualisation.libvirtd.enable = true;
  virtualisation.qemu.package = pkgs.qemu_full;
  virtualisation.qemu.vms.windows11 = {
    # 8 GB RAM, 1/3 of your cores (~8 vCPUs on a 24-thread i7-13700K)
    memory = 8192;
    vcpus  = 8;
    cpu    = "host-passthrough";

    firmware = {
      type        = "uefi";
      codePackage = pkgs.OVMF;
    };

    # Raw NVMe block device for your Windows disk
    disks = [
      { device = "block"; path = "/dev/nvme0n1"; format = "raw"; }
      # CD-ROM for Windows installer ISO (see below)
      { device = "cdrom"; path = "/home/nicholas/Documents/windows11.iso"; }
    ];

    networkBridge = "br0";
    graphics     = { type = "spice"; };

    # Hand the Intel iGPU (now at /dev/vfio/0) to the VM
    hostDevices = [
      { devicePath = "/dev/vfio/0"; }
    ];
  };
}
