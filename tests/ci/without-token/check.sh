#!/usr/bin/env bash
# Checks an installation with github-token "": no user nix.conf, Nix works.
set -euo pipefail
conf=${XDG_CONFIG_HOME:-$HOME/.config}/nix/nix.conf
if [[ -e $conf ]]; then
  echo "::error::$conf was written without a token."
  exit 1
fi
nix --version
nix store info
