#!/usr/bin/env bash
# Prints the settings that the action adds to /etc/nix/nix.conf. The inputs
# must have passed check.sh.
#
# Inputs (environment): SUBSTITUTERS, KEYS.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

substituters=() keys=()
mapfile -t substituters < <(words "${SUBSTITUTERS-}")
mapfile -t keys < <(words "${KEYS-}")

cat <<'EOF'
# Written by action-setup-nix.
sandbox = true
sandbox-fallback = false
substituters = https://cache.nixos.org/
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
require-sigs = true
accept-flake-config = false
extra-experimental-features = nix-command flakes
max-jobs = auto
connect-timeout = 10
fallback = true
EOF
if ((${#substituters[@]})); then
  echo "extra-substituters = ${substituters[*]}"
fi
if ((${#keys[@]})); then
  echo "extra-trusted-public-keys = ${keys[*]}"
fi
