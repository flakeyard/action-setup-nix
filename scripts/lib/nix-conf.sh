#!/usr/bin/env bash
# Prints the settings that the action adds to /etc/nix/nix.conf. The inputs
# must have passed step/check.sh.
#
# Inputs (environment): SUBSTITUTERS, KEYS.
set -euo pipefail
# Builtins only until env.sh replaces PATH.
here=${BASH_SOURCE[0]%/*}
# shellcheck source-path=SCRIPTDIR source=env.sh
source "$here/env.sh"
# shellcheck source-path=SCRIPTDIR source=text.sh
source "$here/text.sh"

substituters=() keys=()
mapfile -t substituters < <(words "${SUBSTITUTERS-}")
mapfile -t keys < <(words "${KEYS-}")
# Shared with update/check-tarball.py, which checks the releases with it.
cache_key=$(<"$here/cache-public-key")

cat <<EOF
# Written by action-setup-nix.
sandbox = true
sandbox-fallback = false
substituters = https://cache.nixos.org/
trusted-public-keys = $cache_key
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
