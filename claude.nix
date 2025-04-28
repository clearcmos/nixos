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
      if [ ! -d "$NPM_CONFIG_PREFIX/node_modules/@anthropic-ai/claude-code" ]; then
        echo "Installing Claude CLI to $HOME/.npm-global..."
        # Set temporary PATH to ensure npm can find its modules
        PATH="${pkgs.nodejs}/bin:$PATH" ${pkgs.nodejs}/bin/npm install --prefix "$NPM_CONFIG_PREFIX" @anthropic-ai/claude-code
      fi
      
      # The correct path to the Claude CLI
      CLAUDE_CLI="$NPM_CONFIG_PREFIX/node_modules/@anthropic-ai/claude-code/cli.js"
      
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
    
    # Source environment variables from /etc/nixos/.env
    ENV_FILE="/etc/nixos/.env"
    if [ -f "$ENV_FILE" ]; then
      echo "Loading environment variables from $ENV_FILE"
      
      # Simple variable loading without using sed
      while IFS='=' read -r key value || [ -n "$key" ]; do
        # Skip comments and empty lines
        if [ "''${key:0:1}" = "#" ] || [ -z "$key" ]; then
          continue
        fi
        # Export the variable without complex processing
        export "$key=$value"
        echo "Loaded: $key"
      done < "$ENV_FILE"
      
      # Debug - check if variables are set
      echo "Debug: CLAUDE_USER_ID is set to: $CLAUDE_USER_ID"
      
      # Create Claude configuration JSON with sensitive data from environment variables
      cat > /tmp/.claude.json << EOF
{
  "numStartups": 3,
  "customApiKeyResponses": {
    "approved": [],
    "rejected": []
  },
  "tipsHistory": {
    "memory-command": 1,
    "theme-command": 2,
    "prompt-queue": 3
  },
  "userID": "$CLAUDE_USER_ID",
  "oauthAccount": {
    "accountUuid": "$CLAUDE_ACCOUNT_UUID",
    "emailAddress": "$CLAUDE_EMAIL",
    "organizationUuid": "$CLAUDE_ORG_UUID",
    "organizationRole": "admin",
    "workspaceRole": "workspace_developer"
  },
  "primaryApiKey": "$CLAUDE_API_KEY",
  "hasCompletedOnboarding": true,
  "lastOnboardingVersion": "0.2.76",
  "changelogLastFetched": $(date +%s)000,
  "projects": {
    "/home/nicholas": {
      "allowedTools": [],
      "history": [],
      "dontCrawlDirectory": true,
      "mcpContextUris": [],
      "mcpServers": {},
      "enabledMcpjsonServers": [],
      "disabledMcpjsonServers": [],
      "enableAllProjectMcpServers": false,
      "hasTrustDialogAccepted": false,
      "ignorePatterns": [],
      "lastCost": 0,
      "lastAPIDuration": 0,
      "lastDuration": 0,
      "lastLinesAdded": 0,
      "lastLinesRemoved": 0,
      "lastSessionId": ""
    }
  },
  "cachedChangelog": "-"
}
EOF

      # Setup for root user
      mkdir -p /root
      cp -f /tmp/.claude.json /root/.claude.json
      chmod 600 /root/.claude.json
      
      # Setup for regular user - hardcoded to nicholas
      USER_HOME="/home/nicholas"
      mkdir -p "$USER_HOME"
      cp -f /tmp/.claude.json "$USER_HOME/.claude.json"
      chmod 600 "$USER_HOME/.claude.json"
      chown "nicholas:users" "$USER_HOME/.claude.json"
      
      # Clean up
      rm -f /tmp/.claude.json
      
      echo "Claude configuration created successfully."
    else
      echo "Error: Environment file not found at $ENV_FILE"
      echo "Please create this file with the following variables:"
      echo "CLAUDE_API_KEY=your-api-key"
      echo "CLAUDE_USER_ID=your-user-id"
      echo "CLAUDE_ACCOUNT_UUID=your-account-uuid"
      echo "CLAUDE_EMAIL=your-email"
      echo "CLAUDE_ORG_UUID=your-org-uuid"
      exit 1
    fi
  '';
}
