# NixOS Fresh Installation Guide (Starting from Scratch)

## 1. Getting the NixOS Installation Media

```bash
# Download the NixOS ISO from https://nixos.org/download.html
# Create a bootable USB drive using a tool like:
# - Rufus (Windows)
# - dd (Linux): sudo dd if=nixos-*.iso of=/dev/sdX bs=4M status=progress
# - Etcher (cross-platform)

# Boot from the USB drive
```

## 2. Partitioning and Formatting

```bash
# List available disks
lsblk

# Partition your disk (example with /dev/sda - replace with your device)
sudo fdisk /dev/sda
# Commands in fdisk:
# g - create new GPT partition table
# n - create new partition (for EFI, +512M)
# t - change partition type (to EFI - type 1)
# n - create another partition (for root, use remaining space)
# w - write changes and exit

# Format the partitions
sudo mkfs.fat -F 32 /dev/sda1  # EFI partition
sudo mkfs.ext4 /dev/sda2       # Root partition

# Mount partitions
sudo mount /dev/sda2 /mnt
sudo mkdir -p /mnt/boot
sudo mount /dev/sda1 /mnt/boot
```

## 3. Generate the Initial Configuration

```bash
# Generate the hardware-specific configuration for this machine
sudo nixos-generate-config --root /mnt
```

## 4. Create Your Basic Configuration

```bash
# Edit the main configuration file
sudo nano /mnt/etc/nixos/configuration.nix
```

## 5. Basic Configuration Template

Replace the content of `/mnt/etc/nixos/configuration.nix` with:

```nix
{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan
      ./hardware-configuration.nix
    ];

  # Use the systemd-boot EFI boot loader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Set your hostname
  networking.hostName = "nix";
  
  # Configure network
  networking.useDHCP = true;
  networking.defaultGateway = "192.168.1.1";
  networking.nameservers = [ "8.8.8.8" "8.8.4.4" ]; # Google DNS, change if needed

  # Set your time zone
  time.timeZone = "America/New_York"; # Change to your timezone

  # Select internationalisation properties
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  # Enable the X11 windowing system and GNOME Desktop Environment
  # Uncomment these if you want a graphical environment
  # services.xserver.enable = true;
  # services.xserver.displayManager.gdm.enable = true;
  # services.xserver.desktopManager.gnome.enable = true;

  # Define a user account
  users.users.your-user-name = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # Enable 'sudo' for this user
    initialPassword = "1234"; # Change this after first login!
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile
  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    htop
    firefox
  ];

  # Enable OpenSSH service if needed
  # services.openssh.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  system.stateVersion = "23.05"; # KEEP THIS VALUE! DO NOT CHANGE IT!
}
```

## 6. Install NixOS

```bash
# Install NixOS with your configuration
sudo nixos-install

# Set root password when prompted
# (You'll need this for the first login if you don't have auto-login configured)
```

## 7. Finalize and Reboot

```bash
# Unmount everything
sudo umount -R /mnt

# Reboot into your new NixOS system
sudo reboot
```

## After Reboot

1. Log in with the user account you defined (`myuser` in the example) or the root account
2. Change your initial password immediately: `passwd`
3. Update your system: `sudo nixos-rebuild switch --upgrade`
4. If needed, make any adjustments to `/etc/nixos/configuration.nix` and run `sudo nixos-rebuild switch`

## Basic Maintenance Commands

```bash
# Update your system
sudo nixos-rebuild switch --upgrade

# Edit your configuration
sudo nano /etc/nixos/configuration.nix

# Apply configuration changes
sudo nixos-rebuild switch

# Rollback to previous configuration if something breaks
sudo nixos-rebuild switch --rollback
```

Remember to customize the example configuration with your preferences for time zone, user names, and packages before installation.
