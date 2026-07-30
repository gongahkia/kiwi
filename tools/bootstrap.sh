#!/usr/bin/env zsh
set -euo pipefail

required_commands=(luajit love stylua make)
for required_command in "${required_commands[@]}"; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    print -u2 "missing required command: $required_command"
    exit 1
  fi
done

print "luajit: $(luajit -v 2>&1)"
print "love: $(love --version)"
print "stylua: $(stylua --version)"
print "bootstrap checks passed"
