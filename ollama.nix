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
  ];

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

  # Create directories for Ollama 
  systemd.tmpfiles.rules = [
    "d /var/lib/ollama 0755 ollama ollama -"
  ];
  
  # Open WebUI configuration - Using custom service
  systemd.services.open-webui = {
    description = "Open WebUI for Ollama";
    wantedBy = ["multi-user.target"];
    after = ["network.target"];
    
    serviceConfig = {
      DynamicUser = true;
      StateDirectory = "open-webui";
      WorkingDirectory = "/var/lib/open-webui";
      ReadWritePaths = ["/var/lib/open-webui"];
      # Create required directories
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /var/lib/open-webui/data /var/lib/open-webui/static";
      ExecStart = "${pkgs.open-webui}/bin/open-webui serve --host 0.0.0.0 --port 8080";
      # Needed for NixOS
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
    };
    
    environment = {
      OLLAMA_API_BASE_URL = "http://127.0.0.1:11434";
      DEFAULT_MODEL = "qwen2.5-coder:32b";
      EMBEDDING = "disabled";
      DISABLE_EMBEDDINGS = "true";
      # Tell Open WebUI where to store its data
      OPENWEBUI_DATA_DIRECTORY = "/var/lib/open-webui";
      DATA_DIR = "/var/lib/open-webui/data";
      # Keep HF cache in our writable directory
      HF_HOME = "/var/lib/open-webui/hf_cache";
      SENTENCE_TRANSFORMERS_HOME = "/var/lib/open-webui/sentence_transformers";
      STATIC_DIR = "/var/lib/open-webui/static";
      # Essential to avoid writing to Nix store
      SKIP_PREPARE = "true";
    };
  };
  
  # Open firewall port
  networking.firewall.allowedTCPPorts = [ 8080 ];
  
}
