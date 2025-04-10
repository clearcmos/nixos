# Certbot SSL Certificate Management in NixOS

This document explains how certbot is set up and integrated with nginx in this NixOS configuration.

## Overview

Certbot is configured in this NixOS system to provide automatic SSL certificate generation and renewal through Let's Encrypt. The implementation includes:

1. Integration with the NixOS ACME module (for certificate management)
2. Nginx plugin support for automatic configuration
3. Shared SSL parameters for consistent security settings
4. Automatic renewal via systemd timers

## Key Files and Locations

- **Certificates**: Stored in `/var/lib/acme/` (one directory per domain)
- **SSL Parameters**: Created in `/etc/nginx/ssl/`
  - `options-ssl-nginx.conf`: Contains secure SSL configuration options
  - `ssl-dhparams.pem`: Contains Diffie-Hellman parameters for key exchange

## Configuring Certificates for Domains

To configure SSL certificates for your domains, you can add them to your host-specific configuration file (e.g., `/etc/nixos/hosts/misc/configuration.nix`).

### Basic Example

Here's an example of configuring a certificate for a domain:

```nix
security.acme.certs = {
  "example.com" = {
    extraDomainNames = [ "www.example.com" ]; # Optional additional domains
    webroot = "/var/lib/acme/acme-challenge";
    email = "your-email@example.com"; # Override the default email if needed
    postRun = "systemctl reload nginx.service"; # Reload nginx after renewal
  };
};
```

### With Nginx Integration

For each domain with a certificate, you'll need to configure an nginx virtual host:

```nix
services.nginx.virtualHosts."example.com" = {
  enableACME = true; # Enables automatic certificate management 
  forceSSL = true;   # Redirects HTTP to HTTPS
  
  # Standard nginx configuration
  locations."/" = {
    root = "/var/www/example.com";
    index = "index.html";
  };
  
  # Optional: Include the shared SSL parameters
  extraConfig = ''
    include /etc/nginx/ssl/options-ssl-nginx.conf;
    ssl_dhparam /etc/nginx/ssl/ssl-dhparams.pem;
  '';
};
```

## Automatic Certificate Renewal

Certificates are automatically renewed via built-in systemd timers. The NixOS ACME module handles this for you, running renewal attempts when certificates are nearing expiration.

To check the renewal status:
```bash
systemctl status acme-*
```

## Manual Commands

While automatic processes handle most tasks, you can manually interact with certificates using the following commands:

### Check Certificate Status
```bash
sudo ls -l /var/lib/acme/
sudo certbot certificates
```

### Force Certificate Renewal
```bash
sudo systemctl start acme-renewal-example.com.service
```

### Test Certificate Configuration
```bash
sudo nginx -t
```

## Troubleshooting

If you encounter issues with certificate issuance or renewal:

1. Check that your domain's DNS is correctly pointed to your server
2. Ensure ports 80 and 443 are open and accessible from the internet
3. Verify that nginx is properly configured for the domain
4. Check the certbot logs: `journalctl -u acme-example.com.service`
5. Try running a manual renewal with verbosity: 
   ```bash
   sudo nixos-container run certbot -- certbot renew --force-renewal --verbose
   ```

## Implementation Details

### NixOS ACME Module

The implementation uses the built-in NixOS ACME module (`security.acme`) which manages the entire certificate lifecycle. This is the modern NixOS way to handle Let's Encrypt certificates.

### Shared SSL Parameters

The system creates two important SSL parameter files:

1. `options-ssl-nginx.conf`: Contains recommended SSL settings including:
   - SSL protocols (TLSv1.2, TLSv1.3)
   - Strong ciphers
   - HSTS headers
   - Other security headers

2. `ssl-dhparams.pem`: Contains Diffie-Hellman parameters for secure key exchange

These files are automatically created during system activation and can be referenced in your nginx configurations.

### Certificate Auto-renewal

The ACME module sets up systemd timers to check certificates twice daily and renew them when they're within 30 days of expiration. This matches the behavior of the cron jobs on Debian systems.