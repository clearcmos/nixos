# CLAUDE INSTRUCTIONS

## Documentation Reference Policy

1. ONLY load and reference files from `/etc/nixos/docs/*.md` when specifically requested (when user broadly asks about checking docs).

2. When a user asks about a topic like "rdp" or "remote desktop", load and reference `/etc/nixos/docs/rdp.md`. This is a general idea, but should work broadly.

3. DO NOT reference files under the docs directory unless specifically asked about the topic vaguely matching filename.

4. Always run the following commands when NixOS configurations are updated:
   - `nixos-rebuild switch` for applying changes permanently, don't test unless I ask you.

5. For configuration issues, always check service status, logs, and relevant configuration files.

## Standard Troubleshooting Procedure

When troubleshooting NixOS services:

1. Check if the service is running:
   ```bash
   systemctl status <service-name>
   ```

2. View recent logs:
   ```bash
   journalctl -u <service-name> -n 50
   ```

3. Verify configuration files with appropriate tools based on the service type.

4. Test configuration changes before applying permanently:
   ```bash
   nixos-rebuild test
   ```

5. Apply working changes permanently:
   ```bash
   nixos-rebuild switch
   ```

## Windows VM with GPU Passthrough Setup

### Key Configuration Steps (2025-05-08)

1. **Basic VM setup**:
   - Configuration file: `/etc/nixos/windows.nix`
   - Uses raw block device `/dev/nvme1n1` with VirtIO drivers
   - Static MAC address: `52:54:00:11:22:33`
   - Reserved IP address: `192.168.1.12`

2. **Intel iGPU passthrough configuration**:
   - Enable IOMMU and VFIO in kernel:
     ```nix
     boot.kernelParams = [ 
       "intel_iommu=on" 
       "iommu=pt" 
       "vfio-pci.ids=8086:a780" 
       "pcie_acs_override=downstream,multifunction"
     ];
     
     boot.kernelPackages = pkgs.linuxPackages_zen;
     boot.blacklistedKernelModules = [ "i915" ];
     ```

3. **Early iGPU binding to VFIO**:
   ```nix
   boot.initrd.preDeviceCommands = ''
     DEVS="0000:00:02.0"  # Intel iGPU
     for DEV in $DEVS; do
       echo "vfio-pci" > /sys/bus/pci/devices/$DEV/driver_override
     done
     modprobe -i vfio-pci
   '';
   ```

4. **Troubleshooting steps**:
   - Verify IOMMU is enabled in BIOS/UEFI
   - Check iGPU is in an IOMMU group after reboot:
     ```bash
     find /sys/kernel/iommu_groups/ -type l | grep "0000:00:02.0"
     ```
   - Verify vfio-pci binding:
     ```bash
     lspci -v | grep -i vga
     ls -la /sys/bus/pci/devices/0000:00:02.0/driver
     ```
   - Check VM status with virt-manager or:
     ```bash
     virsh list --all
     systemctl status windows11-guest
     ```

5. **Required before GPU passthrough works**:
   - Reboot after applying changes
   - Enable VT-d/IOMMU in BIOS
   - Ensure no host software is using the iGPU
