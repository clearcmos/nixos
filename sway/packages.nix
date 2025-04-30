{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    cockpit
    discord
    ffmpeg
    fzf
    htop
    jq
    ncdu
    pandoc
    python3
    radeontop
    rclone
    spotify
    sqlite
    tldr
    (vscode-with-extensions.override {
      vscodeExtensions = with vscode-extensions; [
        bbenoist.nix
        github.copilot
      ];
    })
    wget
  ];
}