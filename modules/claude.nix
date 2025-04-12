{ config, pkgs, lib, ... }:

let
  # Use username from configuration.nix's imported definitions
  username = config.mainUser.username;

  # Helper function to load environment variables from .env file
  loadEnvFile = file:
    let
      content = builtins.readFile file;
      # Handle empty content case
      lines = if content == "" then [] else 
              builtins.filter (l: l != "" && builtins.substring 0 1 l != "#")
                             (lib.splitString "\n" content);
      parseLine = l:
        let
          parts = lib.splitString "=" l;
          key = builtins.head parts;
          value = builtins.concatStringsSep "=" (builtins.tail parts);
        in { name = key; value = value; };
      envVars = builtins.listToAttrs (map parseLine lines);
    in envVars;

  # Attempt to load the .env file, or use empty set if it doesn't exist
  envFile = "/etc/nixos/.env";
  envExists = builtins.pathExists envFile;
  env = if envExists then loadEnvFile envFile else {};

  # Function to get a value from the env file with a default
  getEnv = name: default: if builtins.hasAttr name env
                         then env.${name}
                         else default;
  
  # Get API keys and other sensitive values from .env
  primaryApiKey = getEnv "PRIMARY_API_KEY" "";
  userID = getEnv "USER_ID" "";
  accountUuid = getEnv "ACCOUNT_UUID" "";
  emailAddress = getEnv "EMAIL_ADDRESS" "";
  organizationUuid = getEnv "ORGANIZATION_UUID" "";
  organizationRole = getEnv "ORGANIZATION_ROLE" "";
  workspaceRole = getEnv "WORKSPACE_ROLE" "";
  approvedApiKey = getEnv "APPROVED_API_KEY" "";
  
  # Create Claude configuration content with values from .env
  claudeConfigContent = ''
    {
      "numStartups": ${getEnv "NUM_STARTUPS" "1"},
      "customApiKeyResponses": {
        "approved": [
          "${approvedApiKey}"
        ],
        "rejected": []
      },
      "userID": "${userID}",
      "oauthAccount": {
        "accountUuid": "${accountUuid}",
        "emailAddress": "${emailAddress}",
        "organizationUuid": "${organizationUuid}",
        "organizationRole": "${organizationRole}",
        "workspaceRole": "${workspaceRole}"
      },
      "primaryApiKey": "${primaryApiKey}",
      "hasCompletedOnboarding": ${getEnv "HAS_COMPLETED_ONBOARDING" "true"},
      "lastOnboardingVersion": "${getEnv "LAST_ONBOARDING_VERSION" "0.2.64"}",
      "projects": {
        "${getEnv "PROJECT_PATH" "/home/${username}"}": {
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
          "lastCost": ${getEnv "LAST_COST" "0"},
          "lastAPIDuration": ${getEnv "LAST_API_DURATION" "0"},
          "lastDuration": ${getEnv "LAST_DURATION" "24997"},
          "lastLinesAdded": ${getEnv "LAST_LINES_ADDED" "0"},
          "lastLinesRemoved": ${getEnv "LAST_LINES_REMOVED" "0"},
          "lastSessionId": "${getEnv "LAST_SESSION_ID" "3e3cd966-4033-446c-a1e0-c5c444df0462"}"
        }
      }
    }
  '';

  # Create a helper script that will be packaged properly by Nix
  copyClaudeConfigScript = pkgs.writeShellScriptBin "copy-claude-config" ''
    #!/bin/bash
    USERNAME="${username}"
    USER_HOME="/home/$USERNAME"
    CLAUDE_DIR="$USER_HOME/.claude"
    SOURCE_CONFIG="/etc/nixos/private/.claude.json"

    if [ -d "$USER_HOME" ] && [ -f "$SOURCE_CONFIG" ]; then
      # Create .claude directory if it doesn't exist
      mkdir -p "$CLAUDE_DIR"

      # Copy configuration from source file to both locations
      cp "$SOURCE_CONFIG" "$USER_HOME/.claude.json"
      cp "$SOURCE_CONFIG" "$CLAUDE_DIR/config.json"

      # Set proper ownership and permissions
      chown $USERNAME:users "$USER_HOME/.claude.json"
      chmod 600 "$USER_HOME/.claude.json"
      chown -R $USERNAME:users "$CLAUDE_DIR"
      chmod 700 "$CLAUDE_DIR"
      chmod 600 "$CLAUDE_DIR/config.json"

      echo "Copied Claude configuration from $SOURCE_CONFIG to $USER_HOME/.claude.json and $CLAUDE_DIR/config.json"
    else
      if [ ! -f "$SOURCE_CONFIG" ]; then
        echo "Source config file $SOURCE_CONFIG does not exist"
      else
        echo "User home directory $USER_HOME does not exist yet"
      fi
    fi
  '';
in
{
  # Create a systemd service for installing Claude Code
  systemd.services.claude-code-install = {
    description = "Install Claude Code";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.nodejs ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      echo "Checking for Claude Code..."
      # Create a directory for global npm packages in a writable location
      mkdir -p /opt/npm-global
      mkdir -p /opt/npm-global/bin
      # Create a symlink to node in a directory that will be in PATH
      ln -sf ${pkgs.nodejs}/bin/node /opt/npm-global/bin/node
      # Set npm to use this directory instead of the read-only Nix store
      ${pkgs.nodejs}/bin/npm config set prefix '/opt/npm-global'
      # Make sure the directory is owned by the right user and has correct permissions
      chown -R root:root /opt/npm-global
      chmod -R 755 /opt/npm-global
      # Ensure PATH includes the npm global bin and node's location
      export PATH="/opt/npm-global/bin:${pkgs.nodejs}/bin:$PATH"
      # Set the shell explicitly for npm
      export npm_config_script_shell="${pkgs.bash}/bin/bash"
      echo "Installing Claude Code..."
      ${pkgs.nodejs}/bin/npm install -g @anthropic-ai/claude-code --no-fund --no-audit --loglevel verbose --unsafe-perm=true
    '';
  };

  # Make the Claude Code command available systemwide
  environment.systemPackages = with pkgs; [
    # Add our helper script to system packages
    copyClaudeConfigScript
    # Add a wrapper script for claude
    (pkgs.writeShellScriptBin "claude" ''
      export PATH="/opt/npm-global/bin:$PATH"
      if [ -f "/opt/npm-global/bin/claude" ]; then
        exec /opt/npm-global/bin/claude "$@"
      else
        echo "Claude Code is not installed. Please wait for the claude-code-install service to complete."
        echo "Check status with: systemctl status claude-code-install"
        exit 1
      fi
    '')
  ];

  # Add npm global bin to the system PATH
  environment.extraOutputsToInstall = [ "bin" ];
  environment.pathsToLink = [ "/bin" ];

  # Create a profile script to ensure PATH is set for all shells
  environment.etc."profile.d/npm-global.sh".text = ''
    export PATH="/opt/npm-global/bin:$PATH"
  '';

  # Create a systemd service to ensure config exists in the right locations
  systemd.services.claude-config-setup = {
    description = "Setup Claude Code configuration files";
    after = [ "claude-code-install.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ copyClaudeConfigScript ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      # Ensure the config exists in root's home directory
      mkdir -p /root
      SOURCE_CONFIG="/etc/nixos/private/.claude.json"
      if [ -f "$SOURCE_CONFIG" ]; then
        cp "$SOURCE_CONFIG" /root/.claude.json
        chown root:root /root/.claude.json
        chmod 600 /root/.claude.json
      else
        echo "Source config file $SOURCE_CONFIG does not exist"
      fi

      # Run the script to copy to user's home
      copy-claude-config
    '';
  };

  # Set up a dedicated service that runs on a timer to ensure config exists
  systemd.services.claude-config-copy = {
    description = "Ensure Claude Code configuration files exist";
    after = [ "claude-code-install.service" ];
    wantedBy = [ "multi-user.target" ];
    startAt = "boot";
    path = [ copyClaudeConfigScript ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${copyClaudeConfigScript}/bin/copy-claude-config";
      # Prevent too many rapid starts
      StartLimitIntervalSec = "30";
      StartLimitBurst = "2";
    };
  };

  # Use a NixOS activation script as a primary method to ensure the config is always copied
  # This runs during every nixos-rebuild
  system.activationScripts.copyClaudeConfig = lib.stringAfter [ "users" "groups" ] ''
    echo "Setting up Claude configuration files..."
    USER_HOME="/home/${username}"
    SOURCE_CONFIG="/etc/nixos/private/.claude.json"
    
    if [ -d "$USER_HOME" ] && [ -f "$SOURCE_CONFIG" ]; then
      # Copy to user's locations
      cp "$SOURCE_CONFIG" "$USER_HOME/.claude.json"
      chown ${username}:users "$USER_HOME/.claude.json"
      chmod 600 "$USER_HOME/.claude.json"
      
      # Also copy to the .claude directory
      CLAUDE_DIR="$USER_HOME/.claude"
      mkdir -p "$CLAUDE_DIR"
      cp "$SOURCE_CONFIG" "$CLAUDE_DIR/config.json"
      chown -R ${username}:users "$CLAUDE_DIR"
      chmod 700 "$CLAUDE_DIR"
      chmod 600 "$CLAUDE_DIR/config.json"
      
      # Copy to root's home as well
      mkdir -p /root
      cp "$SOURCE_CONFIG" /root/.claude.json
      chown root:root /root/.claude.json
      chmod 600 /root/.claude.json
      
      echo "Copied Claude configuration from $SOURCE_CONFIG to user and root directories"
    else
      if [ ! -f "$SOURCE_CONFIG" ]; then
        echo "Source config file $SOURCE_CONFIG does not exist"
      else
        echo "User home directory not found at $USER_HOME"
      fi
    fi
  '';
}