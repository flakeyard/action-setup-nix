# shellcheck shell=bash disable=SC2154,SC2034 # shared with tests/harness
# Unit tests of scripts/lib/nix-conf.sh.

setup
run "nix-conf: defaults" ok lib/nix-conf.sh
expect message "sandbox = true"
expect message "sandbox-fallback = false"
expect message "substituters = https://cache.nixos.org/"
expect message "accept-flake-config = false"
expect no-message "extra-substituters"
expect no-message "extra-trusted-public-keys"
finish

setup
run "nix-conf: extra caches on one line each" ok lib/nix-conf.sh \
  SUBSTITUTERS=$'https://a.example.org\n https://b.example.org' KEYS="$key"
expect message "extra-substituters = https://a.example.org https://b.example.org"
expect message "extra-trusted-public-keys = $key"
finish
