#!/usr/bin/env bash
# Checks an installation made by the action on a real runner.
# Usage: tests/ci/install/check.sh
# Inputs (environment): NIX_VERSION (output of the action), EXTRA_SUBSTITUTER,
# SHELL_LIB.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.."

# shellcheck source=/dev/null # the library, from SHELL_LIB
source "$SHELL_LIB/report.sh"

echo "::group::Runner"
# shellcheck disable=SC1091 # the runner's file
. /etc/os-release
echo "$PRETTY_NAME, $(uname -m), XDG_CONFIG_HOME=${XDG_CONFIG_HOME-unset}"
cat /etc/nix/nix.conf
echo "::endgroup::"

[[ $(command -v nix) == /nix/var/nix/profiles/default/bin/nix ]] ||
  fail "nix on PATH is $(command -v nix)."
[[ $(nix --version) == "nix (Nix) $NIX_VERSION" ]] ||
  fail "nix --version is '$(nix --version)', the action reported $NIX_VERSION."

conf=${XDG_CONFIG_HOME:-$HOME/.config}/nix/nix.conf
[[ $(stat -c %a "$conf") == 600 ]] || fail "$conf has mode $(stat -c %a "$conf")."
grep -q '^access-tokens = github.com=' "$conf" || fail "No token in $conf."

[[ $(nix config show trusted-users) == root ]] ||
  fail "trusted-users is '$(nix config show trusted-users)'."
substituters=$(nix config show substituters)
[[ $substituters == *https://cache.nixos.org/* && $substituters == *"$EXTRA_SUBSTITUTER"* ]] ||
  fail "substituters are '$substituters'."
[[ $(nix config show sandbox-paths) == */bin/sh=* ]] ||
  fail "The sandbox has no /bin/sh: $(nix config show sandbox-paths)."

echo "::group::Substituter given on the command line"
output=$(nix store info --option extra-substituters https://untrusted.invalid 2>&1) ||
  fail "nix store info failed: $output"
echo "$output"
echo "::endgroup::"
[[ $output == *"ignoring untrusted substituter 'https://untrusted.invalid'"* ]] ||
  fail "A substituter given by the runner user was not reported as ignored."

echo "::group::Network check outside the sandbox"
if sh tests/ci/install/fixture/no-network.sh; then
  fail "The network check of the fixture passes outside the sandbox, so it proves nothing."
fi
echo "::endgroup::"

# The release that the pinned one replaced, from its fallback-paths.nix: in
# cache.nixos.org, but not installed. Read, not sourced: NIX_VERSION here is
# the output of the action.
previous=$(sed -n 's/^PREVIOUS_NIX_VERSION=//p' versions.sh)
fallback_paths=https://releases.nixos.org/nix/nix-$previous/fallback-paths.nix
path=$(nix eval --raw --impure --expr \
  "(import (builtins.fetchurl \"$fallback_paths\")).$(nix config show system)") ||
  fail "No store path of Nix $previous in $fallback_paths."
echo "::group::Substitution of $path"
nix-store --realise "$path" || fail "$path was not substituted from cache.nixos.org."
nix path-info --sigs "$path"
echo "::endgroup::"

echo "::group::Fetching from GitHub with the token"
nix flake metadata --no-update-lock-file "github:NixOS/nix/$NIX_VERSION" ||
  fail "Fetching a flake from GitHub failed."
echo "::endgroup::"

echo "::group::Sandboxed check"
printf '%s-%s' "$GITHUB_RUN_ID" "$GITHUB_RUN_ATTEMPT" >tests/ci/install/fixture/nonce
output=$(nix flake check --no-update-lock-file --print-build-logs "path:$PWD/tests/ci/install/fixture" 2>&1) ||
  fail "nix flake check failed: $output"
echo "$output"
echo "::endgroup::"
[[ $output == *"ignoring untrusted flake configuration setting 'extra-substituters'"* ]] ||
  fail "The nixConfig of the fixture was not reported as ignored."

echo "Installation checks passed."
