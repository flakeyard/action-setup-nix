#!/usr/bin/env bash
# Checks an installation with github-token "": no user nix.conf, Nix works.
# Inputs (environment): SHELL_LIB.
set -euo pipefail
# shellcheck source=/dev/null # the library, from SHELL_LIB
source "$SHELL_LIB/report.sh"
conf=${XDG_CONFIG_HOME:-$HOME/.config}/nix/nix.conf
[[ ! -e $conf ]] || fail "$conf was written without a token."
nix --version
nix store info
