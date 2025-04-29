# Sunshine Remote Desktop & Game Streaming

This guide explains how to set up and use Sunshine (server) with Moonlight (client) for remote desktop and game streaming on NixOS with Wayland.

## Quick Start Guide

1. **Access the Sunshine Web Interface**:
   - Open `https://localhost:47990` on your NixOS host
   - Create a username and password
   - Configure apps and settings

2. **Connect from a Remote Device**:
   - Install Moonlight client on your remote device
   - Open Moonlight and add your NixOS host
   - If not discovered automatically, enter `hostname:47989` or use your IP address
   - Complete the PIN pairing process when prompted
   - Select your host, then choose Desktop or any other configured app to connect

3. **Recommended Clients**:
   - Windows/macOS/Linux: Moonlight app
   - Android: Moonlight Game Streaming
   - iOS: Moonlight Game Streaming
   - All available at: https://moonlight-stream.org/

## Configuration Details

The remote desktop is configured through `/etc/nixos/sunshine.nix` with the following features:
- Sunshine for the server component (optimized for Wayland)
- Moonlight-qt client for local testing
- Required ports opened automatically in the firewall
- Proper XDG portal support for Wayland screen capture
- System service configuration for automatic startup

### Server Configuration Options

When configuring Sunshine through the web interface, you can adjust:

- **Stream Settings**:
  - Resolution and FPS
  - Video codec (H.264, HEVC, AV1 where supported)
  - Audio configuration
  - Bandwidth and quality settings

- **Application Management**:
  - Add/remove streamable applications
  - Configure launch commands
  - Set icons and display names

- **Security**:
  - Client authorization
  - PIN requirements
  - Connection settings

### Client Connection Instructions

#### From Windows/macOS/Linux:
1. Download and install Moonlight from [moonlight-stream.org](https://moonlight-stream.org/)
2. Launch Moonlight and it should automatically discover your Sunshine host
3. If not discovered, click "Add PC Manually" and enter your host's IP or hostname with port 47989
4. Follow the pairing process and enter the PIN shown in the Moonlight client into Sunshine's web interface
5. Once paired, select your host, then choose Desktop or any configured app to start streaming

#### From Mobile Devices:
1. Install "Moonlight Game Streaming" from your app store
2. Open the app and tap the + button to add a PC
3. Enter your host's IP address or hostname with port 47989
4. Complete the pairing process as described above
5. Tap your host, then select an application to stream

## Security Considerations

1. **Port Forwarding**:
   - Ports 47984, 47989, 47990, 48010 (TCP) and 47998-48000, 8000-8010 (UDP) need to be forwarded for external access
   - Consider using a non-standard port range for additional security

2. **Authentication**:
   - Use a strong password for the Sunshine web interface
   - Keep track of paired clients and unpair any you don't recognize

3. **VPN Recommendation**:
   - For highest security, use a VPN instead of direct internet exposure
   - This ensures encrypted traffic and no direct service exposure

## Troubleshooting

1. **Connection Issues**:
   - Verify Sunshine is running: `systemctl --user status sunshine`
   - Check firewall settings: `sudo nixos-rebuild test` then try connecting
   - Ensure required ports are open and forwarded

2. **Performance Issues**:
   - Adjust video settings in the Sunshine web interface
   - Try different encoding options (H.264 is most compatible, HEVC offers better quality)
   - For best performance, use a wired network connection

3. **Wayland-Specific Issues**:
   - If screen capture doesn't work, verify `capSysAdmin = true` is set in your configuration
   - Make sure XDG portal is properly configured for your desktop environment
   - Some apps may have issues with capturing - try different capture methods in the Sunshine settings

## Additional Information

- Sunshine runs as a systemd user service and starts automatically on login
- Desktop sharing works with both X11 and Wayland sessions
- For optimal performance, an NVIDIA GPU with NVENC or AMD GPU with hardware encoding is recommended
- Sunshine includes a desktop mode and can also stream individual applications

For more assistance, refer to:
- [NixOS Wiki: Sunshine](https://nixos.wiki/wiki/Sunshine)
- [Sunshine GitHub](https://github.com/LizardByte/Sunshine)
- [Moonlight Documentation](https://github.com/moonlight-stream/moonlight-docs/wiki)