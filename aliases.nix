# Shell aliases for NixOS
{
  # Bash is enabled by default in recent NixOS versions
  programs.bash.shellAliases = {
    "ls" = "ls -lh --color=auto --group-directories-first";
    "compress" = "dir=$(basename \"$(pwd)\"); tar -czf \"$${dir}.tar.gz\" ./*";
    "gen" = "openssl rand -base64 45";
    "mine" = "sudo chown -R $(whoami):$(whoami)";
    "port" = "sudo lsof -i -P -n | grep LISTEN | awk '{printf \"%-20s %-10s\\n\", $1, $9}' | sed 's/.*:\\([0-9]*\\)$/\\1/' | sort";
    "rebuild" = "sudo nixos-rebuild switch";
  };
}

