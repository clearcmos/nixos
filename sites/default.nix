# sites/default.nix
# Exports all site configs in this directory
{
  imports = [
    ./scrutiny.nix
    ./glances.nix
  ];
}