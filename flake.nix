{
  description = "Multi-host NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    
    # Additional inputs can be added here as needed
    # Examples:
    # home-manager.url = "github:nix-community/home-manager";
    # home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      
      # Function to create a NixOS system configuration
      mkSystem = { hostname, modules ? [] }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            # Host-specific configuration
            ./hosts/${hostname}
          ] ++ modules;
        };
    in {
      # NixOS configurations for each host
      nixosConfigurations = {
        # misc host configuration
        misc = mkSystem {
          hostname = "misc";
        };
        
        # jellyimmich host configuration
        jellyimmich = mkSystem {
          hostname = "jellyimmich";
        };
        
        # Add more hosts here as needed
      };
    };
}