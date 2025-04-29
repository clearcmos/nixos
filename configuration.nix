programs.bash.loginShellInit = ''
  if [ "$(id -u)" -eq 0 ]; then
    cd /etc/nixos
  fi
'';
