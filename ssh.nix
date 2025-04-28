{ config, pkgs, ... }:

let
  # Read SSH keys from files
  sshKey1 = builtins.readFile ./ssh-keys/authorized/key1;
  sshKey2 = builtins.readFile ./ssh-keys/authorized/key2;
  sshKey3 = builtins.readFile ./ssh-keys/authorized/key3;
  currentUser = config.users.users.nicholas.name;
in {
  # Enable the OpenSSH daemon
  services.openssh = {
    enable = true;
    
    # Custom SSH server configuration
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = false;
      PubkeyAuthentication = true;
      MaxAuthTries = 3;
      LoginGraceTime = 30;
      X11Forwarding = false;
      ClientAliveInterval = 300;
      ClientAliveCountMax = 2;
      Protocol = 2;
      Port = 22;
    };
    
    # Include additional configuration files
    extraConfig = ''
      Include /etc/ssh/sshd_config.d/*.conf
      
      # Allow specific users
      AllowUsers ${currentUser} root
      
      # Restrict SSH access to LAN, WireGuard VPN IPs, and Docker networks
      Match Address 192.168.1.0/24,10.13.13.0/24,192.168.32.0/20
        PermitRootLogin yes
        PubkeyAuthentication yes
      
      Match Address *,!192.168.1.0/24,!10.13.13.0/24,!192.168.32.0/20
        DenyUsers *
    '';
  };
  
  # Add SSH keys to authorized keys for nicholas and root
  users.users.nicholas.openssh.authorizedKeys.keys = [
    sshKey1
    sshKey2
    sshKey3
  ];
  
  users.users.root.openssh.authorizedKeys.keys = [
    sshKey1
    sshKey2
    sshKey3
  ];

  # Create .ssh directories and key files
  system.activationScripts.sshSetup = {
    text = ''
      # Fix permissions on source SSH keys and copy current keys to source
      mkdir -p /etc/nixos/ssh-keys/nicholas
      mkdir -p /etc/nixos/ssh-keys/root
      if [ -f /root/.ssh/id_ed25519 ]; then
        cp -f /root/.ssh/id_ed25519 /etc/nixos/ssh-keys/root/
        cp -f /root/.ssh/id_ed25519.pub /etc/nixos/ssh-keys/root/
      fi
      chmod 600 /etc/nixos/ssh-keys/nicholas/id_ed25519
      chmod 600 /etc/nixos/ssh-keys/root/id_ed25519
      chmod 644 /etc/nixos/ssh-keys/nicholas/id_ed25519.pub
      chmod 644 /etc/nixos/ssh-keys/root/id_ed25519.pub

      # Create nicholas SSH directory and keys
      mkdir -p /home/${currentUser}/.ssh
      chmod 700 /home/${currentUser}/.ssh
      cp /etc/nixos/ssh-keys/nicholas/id_ed25519 /home/${currentUser}/.ssh/id_ed25519
      cp /etc/nixos/ssh-keys/nicholas/id_ed25519.pub /home/${currentUser}/.ssh/id_ed25519.pub
      chmod 600 /home/${currentUser}/.ssh/id_ed25519
      chmod 644 /home/${currentUser}/.ssh/id_ed25519.pub
      chown -R ${currentUser}:users /home/${currentUser}/.ssh

      # Create root SSH directory and keys
      mkdir -p /root/.ssh
      chmod 700 /root/.ssh
      cp /etc/nixos/ssh-keys/root/id_ed25519 /root/.ssh/id_ed25519
      cp /etc/nixos/ssh-keys/root/id_ed25519.pub /root/.ssh/id_ed25519.pub
      chmod 600 /root/.ssh/id_ed25519
      chmod 644 /root/.ssh/id_ed25519.pub
    '';
    deps = [];
  };
}