{
  config,
  pkgs,
  lib,
  ...
}:

let
  user = "nicholas";
  home = "/home/${user}";
in {
  # Install Ollama package with ROCm support and AMD GPU utilities
  environment.systemPackages = with pkgs; [
    ollama-rocm
    pciutils
    rocmPackages.rocm-smi
    aider-chat  # AI pair programming in your terminal
  ];
  
  # Configure environment variables for aider and Ollama
  environment.sessionVariables = {
    # Point aider at your local Ollama server
    OLLAMA_API_BASE = "http://127.0.0.1:11434";
    # Default model for the main chat
    AIDER_MODEL = "ollama_chat/qwen2.5-coder:32b";
    # Suppress missing API key warnings for other providers
    AIDER_SHOW_MODEL_WARNINGS = "false";
  };
  
  # Create aider configuration files
  system.activationScripts.aiderConfig = {
    deps = [ "users" ];
    text = ''
      mkdir -p ${home}/.config/aider
      
      # Tell aider which model to use by default
      cat > ${home}/.config/aider/aider.conf.yml << 'EOF'
model: ollama_chat/qwen2.5-coder:32b
EOF
      
      # Supply context window metadata
      cat > ${home}/.config/aider/model.settings.yml << 'EOF'
- name: ollama_chat/qwen2.5-coder:32b
  extra_params:
    num_ctx: 65536
EOF
      
      # Fix ownership
      chown -R ${user} ${home}/.config/aider
    '';
  };

  # Enable AMD GPU compute support
  hardware.graphics.enable = true;
  hardware.graphics.extraPackages = with pkgs; [
    rocmPackages.clr
    rocmPackages.clr.icd
  ];

  # Ollama service configuration
  systemd.services.ollama = {
    description = "Ollama Service";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.ollama-rocm}/bin/ollama serve";
      Restart = "always";
      User = "ollama";
      Group = "ollama";
      # Add GPU device access
      SupplementaryGroups = [ "video" "render" ];
      Environment = "HSA_OVERRIDE_GFX_VERSION=10.3.0 OLLAMA_CONTEXT_LENGTH=8192";
    };
  };

  # Create a dedicated user and group for Ollama
  users.users.ollama = {
    isSystemUser = true;
    group = "ollama";
    description = "Ollama service user";
    home = "/var/lib/ollama";
    createHome = true;
  };

  users.groups.ollama = {};

  # Create directory for Ollama models
  systemd.tmpfiles.rules = [
    "d /var/lib/ollama 0755 ollama ollama -"
  ];
  
  # Open WebUI configuration
  services.open-webui = {
    enable = true;
    port = 8080;
    openFirewall = true;  # For network access
    environment = {
      OLLAMA_API_BASE_URL = "http://127.0.0.1:11434";
      DEFAULT_MODEL = "deepseek-coder-v2:16b";
    };
  };
}