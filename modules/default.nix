# modules/default.nix
# Exports all modules in this directory
{
  imports = [
    ./cifs-mounts.nix
    ./claude.nix
    ./git.nix
    ./nginx.nix
    ./scrutiny.nix
    ./users.nix
  ];
}