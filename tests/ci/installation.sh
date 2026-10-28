#!/usr/bin/env bash
# Checks an installation made by the action on a real runner.
# Usage: tests/ci/installation.sh
# Inputs (environment): NIX_VERSION (output of the action), EXTRA_SUBSTITUTER.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."

fail() {
  printf '::error::%s\n' "$1"
  exit 1
}

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
if sh tests/fixture/no-network.sh; then
  fail "The network check of the fixture passes outside the sandbox, so it proves nothing."
fi
echo "::endgroup::"

# Nix 2.35.3 from its fallback-paths.nix: in cache.nixos.org, but not installed.
case $(uname -m) in
  x86_64) path=/nix/store/h0klnxidg8az3lpvc2ksan1kk05jkzbk-nix-2.35.3 ;;
  aarch64) path=/nix/store/km1j517ydr6m16qcg0kvm7xc086jhifj-nix-2.35.3 ;;
esac
echo "::group::Substitution of $path"
nix-store --realise "$path" || fail "$path was not substituted from cache.nixos.org."
nix path-info --sigs "$path"
echo "::endgroup::"

echo "::group::Fetching from GitHub with the token"
nix flake metadata --no-write-lock-file github:NixOS/nix/2.35.4 ||
  fail "Fetching a flake from GitHub failed."
echo "::endgroup::"

echo "::group::Sandboxed check"
printf '%s-%s' "$GITHUB_RUN_ID" "$GITHUB_RUN_ATTEMPT" >tests/fixture/nonce
output=$(nix flake check --no-write-lock-file --print-build-logs "path:$PWD/tests/fixture" 2>&1) ||
  fail "nix flake check failed: $output"
echo "$output"
echo "::endgroup::"
[[ $output == *"ignoring untrusted flake configuration setting 'extra-substituters'"* ]] ||
  fail "The nixConfig of the fixture was not reported as ignored."

echo "Installation checks passed."
