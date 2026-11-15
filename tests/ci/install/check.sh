#!/usr/bin/env bash
# Checks an installation made by the action on a real runner.
# Usage: tests/ci/install/check.sh
# Inputs (environment): NIX_VERSION (output of the action), EXTRA_SUBSTITUTER,
# SHELL_LIB.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.."

# shellcheck source=/dev/null # the library, from SHELL_LIB
source "${SHELL_LIB}/report.sh"

echo "::group::Runner"
# shellcheck disable=SC1091 # the runner's file
. /etc/os-release
machine=$(uname -m)
echo "${PRETTY_NAME}, ${machine}, XDG_CONFIG_HOME=${XDG_CONFIG_HOME-unset}"
cat /etc/nix/nix.conf
echo "::endgroup::"

nix_path=$(command -v nix) || fail "No nix on PATH."
[[ ${nix_path} == /nix/var/nix/profiles/default/bin/nix ]] \
  || fail "nix on PATH is ${nix_path}."
version=$(nix --version) || fail "nix --version failed."
[[ ${version} == "nix (Nix) ${NIX_VERSION}" ]] \
  || fail "nix --version is '${version}', the action reported ${NIX_VERSION}."

conf=${XDG_CONFIG_HOME:-${HOME}/.config}/nix/nix.conf
mode=$(stat -c %a "${conf}") || fail "Cannot read the mode of ${conf}."
[[ ${mode} == 600 ]] || fail "${conf} has mode ${mode}."
grep -q '^access-tokens = github.com=' "${conf}" || fail "No token in ${conf}."

trusted_users=$(nix config show trusted-users)
[[ ${trusted_users} == root ]] || fail "trusted-users is '${trusted_users}'."
substituters=$(nix config show substituters)
[[ ${substituters} == *https://cache.nixos.org/* && ${substituters} == *"${EXTRA_SUBSTITUTER}"* ]] \
  || fail "substituters are '${substituters}'."
sandbox_paths=$(nix config show sandbox-paths)
[[ ${sandbox_paths} == */bin/sh=* ]] \
  || fail "The sandbox has no /bin/sh: ${sandbox_paths}."

echo "::group::Substituter given on the command line"
output=$(nix store info --option extra-substituters https://untrusted.invalid 2>&1) \
  || fail "nix store info failed: ${output}"
echo "${output}"
echo "::endgroup::"
[[ ${output} == *"ignoring untrusted substituter 'https://untrusted.invalid'"* ]] \
  || fail "A substituter given by the runner user was not reported as ignored."

echo "::group::Network check outside the sandbox"
if sh tests/ci/install/fixture/no-network.sh; then
  fail "The network check of the fixture passes outside the sandbox, so it proves nothing."
fi
echo "::endgroup::"

# The release that the pinned one replaced, from its fallback-paths.nix: in
# cache.nixos.org, but not installed. Read, not sourced: NIX_VERSION here is
# the output of the action.
previous=$(sed -n 's/^PREVIOUS_NIX_VERSION=//p' versions.sh)
fallback_paths=https://releases.nixos.org/nix/nix-${previous}/fallback-paths.nix
system=$(nix config show system)
path=$(nix eval --raw --impure --expr \
  "(import (builtins.fetchurl \"${fallback_paths}\")).${system}") \
  || fail "No store path of Nix ${previous} in ${fallback_paths}."
echo "::group::Substitution of ${path}"
nix-store --realise "${path}" || fail "${path} was not substituted from cache.nixos.org."
nix path-info --sigs "${path}"
echo "::endgroup::"

echo "::group::Fetching from GitHub with the token"
nix flake metadata --no-update-lock-file "github:NixOS/nix/${NIX_VERSION}" \
  || fail "Fetching a flake from GitHub failed."
echo "::endgroup::"

echo "::group::Sandboxed check"
printf '%s-%s' "${GITHUB_RUN_ID}" "${GITHUB_RUN_ATTEMPT}" >tests/ci/install/fixture/nonce
output=$(nix flake check --no-update-lock-file --print-build-logs "path:${PWD}/tests/ci/install/fixture" 2>&1) \
  || fail "nix flake check failed: ${output}"
echo "${output}"
echo "::endgroup::"
[[ ${output} == *"ignoring untrusted flake configuration setting 'extra-substituters'"* ]] \
  || fail "The nixConfig of the fixture was not reported as ignored."

echo "Installation checks passed."
