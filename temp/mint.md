# Ollama & Open WebUI Deployment With AMD 6800XT GPU on Ubuntu 24.04.2 LTS

This guide provides optimized setup instructions for deploying Ollama with Open WebUI on Ubuntu 24.04 LTS, specifically tailored for AMD RX 6800XT GPUs. This configuration addresses common stability issues and SDDM crashes.

## Prerequisites
Before proceeding, ensure you have the following:
- A machine running Ubuntu 24.04.2 LTS
- An AMD RX 6800XT GPU
- Basic knowledge of Docker and command line operations

## Step 1: Update System and Install Monitoring Tools
```bash
sudo apt update && sudo apt upgrade -y && sudo apt -y install radeontop
```

## Step 2: Install Optimized AMDGPU Configuration

### System-wide GPU Configuration
Create the AMD GPU kernel module configuration:
```bash
sudo mkdir -p /etc/modprobe.d
sudo tee /etc/modprobe.d/amdgpu.conf > /dev/null << 'EOF'
options amdgpu ppfeaturemask=0xfffd3fff
options amdgpu noretry=0
options amdgpu gpu_recovery=1
options amdgpu pcie_atomics=1
EOF
```

### Environment Variables Configuration
Create optimized environment variables for the AMD GPU:
```bash
sudo mkdir -p /etc/environment.d
sudo tee /etc/environment.d/90-amdgpu.conf > /dev/null << 'EOF'
GPU_MAX_HEAP_SIZE=100
GPU_USE_SYNC_OBJECTS=1
ROC_ENABLE_PRE_VEGA=0
RADV_PERFTEST=sam,nggc
EOF
```

## Step 3: Configure Display Server (Choose X11 OR Wayland)

### Option A: For X11 Users
```bash
sudo mkdir -p /etc/X11/xorg.conf.d
sudo tee /etc/X11/xorg.conf.d/20-amdgpu.conf > /dev/null << 'EOF'
Section "Device"
    Identifier "AMD"
    Driver "amdgpu"
    Option "TearFree" "true"
    Option "DRI" "3"
    Option "AccelMethod" "glamor"
    Option "VariableRefresh" "true"
EndSection
EOF

sudo tee /etc/sddm.conf > /dev/null << 'EOF'
[X11]
ServerArguments=-nolisten tcp -dpi 96
EOF
```

### Option B: For Wayland Users
```bash
sudo tee /etc/environment.d/91-amdgpu-wayland.conf > /dev/null << 'EOF'
WLR_DRM_NO_ATOMIC=1
AMD_VULKAN_ICD=RADV
EOF

sudo mkdir -p /etc/sddm.conf.d
sudo tee /etc/sddm.conf.d/wayland.conf > /dev/null << 'EOF'
[Wayland]
EnableHiDPI=true
SessionDir=/usr/share/wayland-sessions
EOF

sudo tee /etc/sddm.conf > /dev/null << 'EOF'
[General]
DisplayServer=wayland

[Wayland]
EnableHiDPI=true
EOF

sudo tee /etc/profile.d/rocm-wayland.sh > /dev/null << 'EOF'
# ROCm environment variables for Wayland
export WLR_RENDERER=vulkan
export AMD_VULKAN_ICD=RADV
EOF

sudo chmod +x /etc/profile.d/rocm-wayland.sh
```

## Step 4: Install the AMDGPU Installer Package
```bash
sudo apt update
wget https://repo.radeon.com/amdgpu-install/6.4/ubuntu/noble/amdgpu-install_6.4.60400-1_all.deb
sudo apt install ./amdgpu-install_6.4.60400-1_all.deb
sudo apt update
```

## Step 5: Install the ROCm Stack
```bash
sudo amdgpu-install --usecase=graphics,rocm --no-dkms
```

## Step 6: Add User to Required Groups
```bash
if ! getent group render > /dev/null 2>&1; then
    sudo groupadd render
fi
if ! getent group video > /dev/null 2>&1; then
    sudo groupadd video
fi
sudo usermod -a -G render,video $LOGNAME
```

## Step 7: Install Docker
```bash
sudo apt install docker.io docker-compose
sudo systemctl enable --now docker
sudo usermod -aG docker $LOGNAME
```

## Step 8: Update Initramfs and Reboot
```bash
sudo update-initramfs -u
sudo reboot
```

## Step 9: Create Docker-Compose Configuration

Create a folder for your Ollama setup:
```bash
mkdir -p ~/ollama-setup
cd ~/ollama-setup
```

Create the docker-compose.yml file:
```bash
tee docker-compose.yml > /dev/null << 'EOF'
version: '3.8'
services:
  ollama:
    image: ollama/ollama:rocm
    container_name: ollama
    restart: always
    ports:
      - "11434:11434"
    volumes:
      - ./data/ollama:/root/.ollama
      - ./modelfile:/modelfile
    devices:
      - /dev/kfd:/dev/kfd
      - /dev/dri:/dev/dri
    group_add:
      - "${RENDER_GROUP_ID:-992}"
      - "video"
    environment:
      - HSA_OVERRIDE_GFX_VERSION=10.3.0
      - HCC_AMDGPU_TARGET=gfx1030
    # Note: These environment variables are contained only within the Docker container
    # and will not affect system stability or cause SDDM crashes

  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    restart: always
    ports:
      - "8080:8080"
    volumes:
      - ./data/webui:/app/backend/data
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
    depends_on:
      - ollama

volumes:
  ollama:
  webui:
EOF
```

## Step 10: Create Necessary Directories and Modelfile
```bash
mkdir -p data/ollama data/webui modelfile

tee modelfile/qwen-coder-60k.modelfile > /dev/null << 'EOF'
FROM qwen2.5-coder:7b
# Set a higher context window (60K)
PARAMETER num_ctx 60000
# Adjust model parameters for better performance
PARAMETER temperature 0.7
PARAMETER top_p 0.9
PARAMETER top_k 40
# System prompt to optimize for code tasks
SYSTEM """
You are a helpful AI programming assistant with expertise in software development.
You excel at code generation, debugging, and providing detailed explanations.
Provide concise, clean, and well-documented code.
"""
EOF
```

## Step 11: Launch the Containers
```bash
cd ~/ollama-setup
docker-compose up -d
```

## Step 12: Create and Test the Custom Model
```bash
docker exec -it ollama ollama create qwen-coder-60k -f /modelfile/qwen-coder-60k.modelfile
docker exec -it ollama ollama run qwen-coder-60k
```

Then type:
```
>>> /show info
```

## Accessing Open WebUI
You should now be able to access Open WebUI via http://localhost:8080.

## Troubleshooting

If you encounter issues:

1. Check system logs for GPU-related errors:
   ```bash
   sudo journalctl -b | grep -i amdgpu
   ```

2. Verify Docker container status:
   ```bash
   docker-compose logs
   ```

3. Monitor GPU utilization:
   ```bash
   radeontop
   ```

4. If you're still experiencing SDDM crashes:
   - Try switching between X11 and Wayland options
   - Ensure all system updates are installed 
   - Remove any conflicting GPU configuration files from previous installations

This optimized setup separates the system-wide AMD GPU configuration (for stability) from the container-specific settings (for AI model performance), ensuring both can work together without conflicts.
