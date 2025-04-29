{
  config,
  pkgs,
  lib,
  ...
}:

# Set to false to disable all AMD GPU optimizations
let
  enableOptimizations = true;
in
{
  # AMD GPU performance optimizations
  boot.kernelParams = if enableOptimizations then [ 
    "amdgpu.pcie_atomics=1"    # Enable PCIE atomics for better performance
    "amdgpu.ppfeaturemask=0xffffffff"  # Enable all power features for better control
  ] else [];
  
  # Load amdgpu module early
  boot.initrd.kernelModules = [ "amdgpu" ];
  
  # Enable hardware acceleration with ROCm packages
  hardware.graphics = {
    enable = true;
    enable32Bit = true;  # For 32-bit application support
    extraPackages = with pkgs; if enableOptimizations then [
      rocmPackages.clr
      rocmPackages.clr.icd
      pciutils
      rocmPackages.rocm-smi
    ] else [];
  };
  
  # System-wide environment variables for ROCm
  environment.variables = if enableOptimizations then {
    HSA_OVERRIDE_GFX_VERSION = "10.3.0";  # For RDNA2 compatibility
    GPU_MAX_HEAP_SIZE = "100";  # Allow more VRAM usage (percentage)
    GPU_USE_SYNC_OBJECTS = "1";  # Better synchronization
    ROC_ENABLE_PRE_VEGA = "0";  # Disable support for pre-Vega GPUs
  } else {};
}