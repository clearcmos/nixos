# NixOS Nginx with GeoIP2 Configuration

This document explains the Nginx configuration with GeoIP2 geographic IP filtering that has been implemented in this NixOS system.

## Overview

The setup consists of:
1. Nginx web server with GeoIP2 module
2. MaxMind GeoIP databases for geolocation
3. Automated database updates via geoipupdate service
4. Country-based filtering for access control

## Configuration Files

- **nginx.nix**: Primary configuration file defining nginx settings and GeoIP integration
- **configuration.nix**: Main system configuration that imports nginx.nix
- **.env**: Contains credentials for MaxMind account 

## GeoIP Implementation

### Database Management

The system automatically downloads and updates the following MaxMind GeoIP2 databases:
- GeoLite2-ASN
- GeoLite2-City 
- GeoLite2-Country

The databases are stored in `/var/lib/GeoIP/` and accessed by nginx for country detection.

### Security Features

1. **Country Whitelisting**: Only allows access from specified countries configured in the `.env` file
2. **Router Exclusion**: Automatically excludes your router IP from restrictions
3. **Rate Limiting**: Implements request rate limiting to prevent abuse

### Credentials Management

MaxMind credentials are securely stored in the `.env` file as:
```
MAXMIND_ACCOUNT_ID=your_account_id
MAXMIND_LICENSE_KEY=your_license_key
WHITELISTED_COUNTRY_CODES="US CA" # Space-separated country codes
ROUTER_IP=192.168.1.1 # Your router IP
```

The system creates a secure key file during activation and configures the geoipupdate service to use it.

## Technical Implementation

### Nginx Module Configuration

The nginx package is built with GeoIP2 support using:
```nix
package = pkgs.nginx.override {
  modules = [ pkgs.nginxModules.geoip2 ];
};
```

### GeoIP Update Service

The system configures the `geoipupdate` service to automatically refresh databases weekly:
```nix
services.geoipupdate = {
  enable = true;
  interval = "weekly";
  settings = {
    AccountID = 123456;
    LicenseKey = "/run/keys/maxmind_license_key";
    EditionIDs = [ "GeoLite2-ASN" "GeoLite2-City" "GeoLite2-Country" ];
  };
};
```

### Country Detection and Filtering

The nginx configuration uses the GeoIP2 module to:
1. Extract the country code from visitor IP addresses
2. Map the country code to an allow/deny status
3. Apply filtering based on the resulting status

## Troubleshooting

If you encounter issues:

1. Check if GeoIP databases exist: `ls -la /var/lib/GeoIP/`
2. Verify geoipupdate service status: `systemctl status geoipupdate.service`
3. Check nginx logs: `journalctl -u nginx.service`
4. Verify nginx configuration: `nginx -t`

## Extending the Configuration

To modify allowed countries:
1. Update the `WHITELISTED_COUNTRY_CODES` in `.env`
2. Rebuild the system: `nixos-rebuild switch`

To test the country filtering:
- Use a VPN to connect from different countries
- Check the nginx access logs to see if the country code is properly detected