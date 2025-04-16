{config, lib, pkgs, ...}:

with lib;

let
  cfg = config.services.openvpn-server;
in
{
  options.services.openvpn-server = {
    enable = mkEnableOption "OpenVPN server";
    
    port = mkOption {
      type = types.port;
      default = 1194;
      description = "Port number for the OpenVPN server";
    };

    protocol = mkOption {
      type = types.enum ["udp" "tcp"];
      default = "udp";
      description = "Protocol to use (UDP or TCP)";
    };
    
    vpnSubnet = mkOption {
      type = types.str;
      default = "10.8.0.0 255.255.255.0";
      description = "VPN subnet to use (format: network netmask)";
    };

    serverPublicIP = mkOption {
      type = types.str;
      description = "Server's public IP address or domain name";
    };
    
    dnsServers = mkOption {
      type = types.listOf types.str;
      default = ["1.1.1.1" "1.0.0.1"];
      description = "DNS servers to push to clients";
    };
    
    routeAllTraffic = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to route all client traffic through the VPN";
    };
    
    additionalConfig = mkOption {
      type = types.lines;
      default = "";
      description = "Additional OpenVPN server configuration";
    };
  };

  config = mkIf cfg.enable {
    # Install and enable OpenVPN server
    services.openvpn.servers.main = {
      config = ''
        # Network configuration
        port ${toString cfg.port}
        proto ${cfg.protocol}
        dev tun

        # Certificates and keys
        ca /var/lib/openvpn/ca.crt
        cert /var/lib/openvpn/server.crt
        key /var/lib/openvpn/server.key
        dh /var/lib/openvpn/dh.pem
        tls-auth /var/lib/openvpn/ta.key 0

        # Network settings
        server ${cfg.vpnSubnet}
        ifconfig-pool-persist /var/lib/openvpn/ipp.txt

        # Pushing routes and DNS to clients
        ${concatMapStrings (dns: "push \"dhcp-option DNS ${dns}\"\n") cfg.dnsServers}
        ${optionalString cfg.routeAllTraffic ''
          push "redirect-gateway def1 bypass-dhcp"
        ''}

        # Various security settings
        keepalive 10 120
        cipher AES-256-CBC
        auth SHA256
        user nobody
        group nobody
        persist-key
        persist-tun
        status /var/log/openvpn/openvpn-status.log
        verb 3
        
        # Additional configuration
        ${cfg.additionalConfig}
      '';
    };

    # Enable packet forwarding
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
    };

    # Open firewall for OpenVPN
    networking.firewall = {
      allowedUDPPorts = mkIf (cfg.protocol == "udp") [ cfg.port ];
      allowedTCPPorts = mkIf (cfg.protocol == "tcp") [ cfg.port ];
    };

    # Add necessary packages
    environment.systemPackages = with pkgs; [
      easy-rsa
    ];

    # Add a helpful setup script for generating certificates
    system.activationScripts.openvpnSetup = ''
      # Create OpenVPN directories if they don't exist
      mkdir -p /var/lib/openvpn
      
      # Display helpful information for certificate setup
      cat > /var/lib/openvpn/README.txt << EOL
OpenVPN Server Setup Guide:

1. Initialize the PKI:
   mkdir -p /etc/openvpn/easy-rsa
   cp -r ${pkgs.easy-rsa}/share/easy-rsa/* /etc/openvpn/easy-rsa/
   cd /etc/openvpn/easy-rsa
   
2. Configure vars:
   Edit the vars file and adjust settings as needed

3. Generate certificates:
   ./easyrsa init-pki
   ./easyrsa build-ca
   ./easyrsa build-server-full server nopass
   ./easyrsa build-client-full client1 nopass
   ./easyrsa gen-dh
   openvpn --genkey --secret ta.key
   
4. Copy files to the proper location:
   cp pki/ca.crt pki/dh.pem pki/issued/server.crt pki/private/server.key ta.key /var/lib/openvpn/

5. Generate client configuration:
   Create a client.ovpn file with the appropriate settings and certificates
EOL
    '';

    # Make sure the OpenVPN log directory exists
    systemd.services.openvpn-main.preStart = ''
      mkdir -p /var/log/openvpn
    '';
  };
}