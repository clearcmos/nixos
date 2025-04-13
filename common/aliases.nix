{
  # Bash is enabled by default in recent NixOS versions
  programs.bash.shellAliases = {
    "ls" = "ls -l --color=auto --group-directories-first";
    "ls -l" = "ls -l --color=auto --group-directories-first";
    "ls -a" = "ls -la --color=auto --group-directories-first";
    "ls -la" = "ls -la --color=auto --group-directories-first";
  };
}
