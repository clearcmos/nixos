{ config, lib, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    cifs-utils
    curl
    fzf
    git
    htop
    jq
    ncdu
    nodejs
    python3
    samba
    smartmontools
    tldr
    tmux
    tree
    unzip
    vim
    wget
  ];

  environment.variables.EDITOR = "vim";
  
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc.lib
    zlib
    openssl
    curl
    expat
    which
    xz
    icu
    zstd
    libsecret
  ];
}