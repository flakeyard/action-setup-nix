#!/usr/bin/env bash
# Checks the installed Nix: its version, the daemon, and that /etc/nix/nix.conf
# holds the settings of lib/nix-conf.sh and nothing else but the installer's.
#
# Inputs (environment): SUBSTITUTERS, KEYS, GITHUB_OUTPUT.
set -euo pipefail
lib=$(dirname -- "${BASH_SOURCE[0]}")/../lib
# shellcheck source-path=SCRIPTDIR source=../lib/env.sh
source "$lib/env.sh"
# shellcheck source-path=SCRIPTDIR source=../lib/runner.sh
source "$lib/runner.sh"

# Only the runner user's own settings, not those of the job environment, such
# as NIX_CONFIG.
nix() {
  env -i PATH="$SYSTEM_PATH" HOME="$HOME" USER="$(id -un)" "$(nix_bin)" "$@"
}
fail() {
  printf '::error::%s\n' "$1"
  exit 1
}

conf=$ROOT/etc/nix/nix.conf
[[ -x $(nix_bin) ]] || fail "$(nix_bin) was not installed."
[[ -r $conf ]] || fail "$conf was not installed."

version=$(nix --version) || fail "nix --version failed."
[[ $version == "nix (Nix) $NIX_VERSION" ]] ||
  fail "Installed '$version', expected Nix $NIX_VERSION."

nix store info >/dev/null || fail "The Nix daemon does not answer."

expected=$("$lib/nix-conf.sh")
actual=$(<"$conf")
[[ $actual == "$expected"$'\n'* ]] ||
  fail "$conf does not start with the settings of this action."
while IFS= read -r line; do
  [[ -z $line || $line == "build-users-group = nixbld" ]] ||
    fail "Unexpected line in $conf: $line"
done <<<"${actual#"$expected"}"

[[ $(nix config show sandbox) == true && $(nix config show sandbox-fallback) == false ]] ||
  fail "The sandbox is not enabled."

echo "Installed Nix $NIX_VERSION."
echo "nix-version=$NIX_VERSION" >>"$GITHUB_OUTPUT"
