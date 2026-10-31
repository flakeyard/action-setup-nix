# shellcheck shell=bash disable=SC2154,SC2034 # shared with tests/harness
# Unit tests of scripts/step/configure-token.sh.

setup
run "token: written for the user only" ok step/configure-token.sh TOKEN=ghs_abc
expect file "$work/home/.config/nix/nix.conf" "access-tokens = github.com=ghs_abc"
expect mode "$work/home/.config/nix/nix.conf" 600
finish

setup
mkdir -p "$work/xdg"
run "token: XDG_CONFIG_HOME" ok step/configure-token.sh TOKEN=ghs_abc XDG_CONFIG_HOME="$work/xdg"
expect file "$work/xdg/nix/nix.conf" "access-tokens = github.com=ghs_abc"
finish

setup
mkdir -p "$work/home/.config/nix"
echo "accept-flake-config = true" >"$work/home/.config/nix/nix.conf"
run "token: does not overwrite a conf it did not write" fail step/configure-token.sh TOKEN=ghs_abc
expect file "$work/home/.config/nix/nix.conf" "accept-flake-config = true"
finish
