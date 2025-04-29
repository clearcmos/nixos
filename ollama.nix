{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Install Ollama package with ROCm support and AMD GPU utilities
  environment.systemPackages = with pkgs; [
    ollama-rocm
    pciutils
    rocmPackages.rocm-smi
    aider-chat  # AI pair programming in your terminal
  ];
  
  # Configure aider to use qwen model by default (system-wide)
  environment.variables = {
    OLLAMA_API_BASE = "http://127.0.0.1:11434";
    AIDER_MODEL = "ollama_chat/qwen2.5-coder:32b";
  };
  
  # Create aider configuration directory and settings for nicholas user
  system.activationScripts.aiderConfig = {
    text = ''
      # Create config directory
      mkdir -p /home/nicholas/.config/aider
      
      # Create model settings file
      cat > /home/nicholas/.config/aider/model.settings.yml << 'EOF'
- name: ollama_chat/qwen2.5-coder:32b
  extra_params:
    num_ctx: 65536
EOF
      
      # Set proper ownership
      chown -R nicholas /home/nicholas/.config/aider
    '';
    deps = [];
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
      Environment = "HSA_OVERRIDE_GFX_VERSION=10.3.0";
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