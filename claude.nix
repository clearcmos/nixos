# Configuration for Claude CLI
{ config, lib, pkgs, ... }:

{
  # Create a wrapper script for the Claude CLI
  environment.systemPackages = with pkgs; [
    (pkgs.writeShellScriptBin "claude" ''
      #!/bin/sh
      
      # Ensure the npm directory exists
      export NPM_CONFIG_PREFIX="$HOME/.npm-global"
      mkdir -p "$NPM_CONFIG_PREFIX/lib/node_modules"
      
      # Check if package is already installed
      if [ ! -d "$NPM_CONFIG_PREFIX/lib/node_modules/@anthropic-ai/claude-code" ]; then
        echo "Installing Claude CLI to $HOME/.npm-global..."
        # Set temporary PATH to ensure npm can find its modules
        PATH="${pkgs.nodejs}/bin:$PATH" ${pkgs.nodejs}/bin/npm install --prefix "$NPM_CONFIG_PREFIX" @anthropic-ai/claude-code
      fi
      
      # The correct path to the Claude CLI (detected from previous run)
      CLAUDE_CLI="$NPM_CONFIG_PREFIX/lib/node_modules/@anthropic-ai/claude-code/cli.js"
      
      # Check if the CLI file exists before trying to execute it
      if [ -f "$CLAUDE_CLI" ]; then
        # Execute the Claude CLI with all arguments
        ${pkgs.nodejs}/bin/node "$CLAUDE_CLI" "$@"
      else
        echo "Claude CLI not found at expected path: $CLAUDE_CLI"
        echo "Searching for Claude CLI in npm directory..."
        
        # Try to find the CLI file
        FOUND_CLI=$(find "$NPM_CONFIG_PREFIX" -name "cli.js" | grep -i claude | head -1)
        if [ -n "$FOUND_CLI" ]; then
          echo "Found Claude CLI at: $FOUND_CLI"
          ${pkgs.nodejs}/bin/node "$FOUND_CLI" "$@"
        else
          echo "Could not locate the Claude CLI. Please check the installation."
          exit 1
        fi
      fi
    '')
  ];

  # Create a systemd activation script to copy Claude configuration file during rebuild
  system.activationScripts.setupClaude = ''
    echo "Setting up Claude configuration files..."
    if [ -f /etc/nixos/.secrets/.claude.json ]; then
      mkdir -p /root
      cp -f /etc/nixos/.secrets/.claude.json /root/.claude.json
      chmod 600 /root/.claude.json
      echo "Claude configuration copied successfully."
    else
      echo "Source config file /etc/nixos/.secrets/.claude.json does not exist"
    fi
  '';
}