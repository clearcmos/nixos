# Ollama & Open WebUI Deployment for AMD 6800XT on Kubuntu 24.04 (KDE Plasma)

This guide provides a specialized setup for deploying Ollama with Open WebUI on Kubuntu 24.04 LTS with KDE Plasma, specifically tailored for AMD RX 6800XT GPUs. This configuration addresses the SDDM login crashes experienced with this GPU.

## Prerequisites
- Kubuntu 24.04 LTS with KDE Plasma
- AMD RX 6800XT GPU
- Basic knowledge of Docker and command line operations

## Step 1: Update System and Install Monitoring Tools
```bash
sudo apt update && sudo apt upgrade -y && sudo apt -y install radeontop
```

## Step 2: Create Critical AMD Configuration Files

First, create the kernel module configuration that matches the working NixOS setup:
```bash
sudo mkdir -p /etc/modprobe.d
sudo tee /etc/modprobe.d/amdgpu.conf > /dev/null << 'EOF'
options amdgpu ppfeaturemask=0xffffffff
options amdgpu pcie_atomics=1
EOF
```

Next, create the environment variables that match the working configuration:
```bash
sudo mkdir -p /etc/environment.d
sudo tee /etc/environment.d/90-amdgpu.conf > /dev/null << 'EOF'
HSA_OVERRIDE_GFX_VERSION=10.3.0
GPU_MAX_HEAP_SIZE=100
GPU_USE_SYNC_OBJECTS=1
ROC_ENABLE_PRE_VEGA=0
EOF
```

## Step 3: KDE Plasma-Specific Configuration

Create a KDE-specific SDDM configuration:
```bash
sudo mkdir -p /etc/sddm.conf.d
sudo tee /etc/sddm.conf.d/kde-gpu.conf > /dev/null << 'EOF'
[X11]
ServerArguments=-nolisten tcp -dpi 96

[Wayland]
EnableHiDPI=true

[General]
DisplayStopCommand=/usr/bin/killall amdgpu_dri
EOF
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
sudo usermod -a -G render,video,input $LOGNAME
```

## Step 7: Create Special KDE Plasma Startup Script

This creates a script that unloads and reloads the GPU module on login:
```bash
sudo tee /etc/X11/Xsession.d/30amdgpu > /dev/null << 'EOF'
#!/bin/sh
# KDE Plasma workaround for AMD 6800XT
if [ "$XDG_SESSION_DESKTOP" = "KDE" ] || [ "$XDG_SESSION_DESKTOP" = "plasma" ]; then
    export HSA_OVERRIDE_GFX_VERSION=10.3.0
    export GPU_MAX_HEAP_SIZE=100
    export GPU_USE_SYNC_OBJECTS=1
    export ROC_ENABLE_PRE_VEGA=0
fi
EOF

sudo chmod +x /etc/X11/Xsession.d/30amdgpu
```

## Step 8: Install Docker
```bash
sudo apt install docker.io docker-compose
sudo systemctl enable --now docker
sudo usermod -aG docker $LOGNAME
```

## Step 9: Update Initramfs and Reboot
```bash
sudo update-initramfs -u
sudo reboot
```

## Step 10: Create Docker-Compose Configuration

Create a folder for your Ollama setup:
```bash
mkdir -p ~/ollama-setup
cd ~/ollama-setup
```

Create the docker-compose.yml file with the exact same environment variables as the system:
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
      - GPU_MAX_HEAP_SIZE=100
      - GPU_USE_SYNC_OBJECTS=1
      - ROC_ENABLE_PRE_VEGA=0

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

## Step 11: Create Necessary Directories and Modelfile
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

## Step 12: Launch the Containers
```bash
cd ~/ollama-setup
docker-compose up -d
```

## Step 13: Create and Test the Custom Model
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

## Additional Troubleshooting for Kubuntu 24.04

If you continue to experience SDDM login issues:

1. Try switching to a different TTY (Ctrl+Alt+F3) when you encounter login issues, and try these commands:
   ```bash
   sudo systemctl restart sddm
   ```

2. Check if the amdgpu module is properly loaded:
   ```bash
   lsmod | grep amdgpu
   ```

3. If all else fails, you might need to try a different display manager:
   ```bash
   sudo apt install lightdm
   sudo dpkg-reconfigure lightdm
   ```

4. Update your GPU firmware:
   ```bash
   sudo apt install amd-firmware
   ```

5. Create a script to restart the display manager if it fails on boot (advanced):
   ```bash
   sudo tee /usr/local/bin/restart-display.sh > /dev/null << 'EOF'
   #!/bin/bash
   sleep 5
   systemctl is-active sddm || systemctl restart sddm
   EOF
   
   sudo chmod +x /usr/local/bin/restart-display.sh
   
   sudo tee /etc/systemd/system/restart-display.service > /dev/null << 'EOF'
   [Unit]
   Description=Restart display manager if it fails
   After=sddm.service
   
   [Service]
   Type=oneshot
   ExecStart=/usr/local/bin/restart-display.sh
   
   [Install]
   WantedBy=multi-user.target
   EOF
   
   sudo systemctl enable restart-display.service
   ```

This configuration specifically addresses the unique way KDE Plasma on Kubuntu 24.04 interacts with the AMD 6800XT GPU, mirroring your working NixOS configuration.
