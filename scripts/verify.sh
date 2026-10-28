#!/usr/bin/env bash
# Checks the installed Nix: its version, the daemon, and that /etc/nix/nix.conf
# holds the settings of nix-conf.sh and nothing else but the installer's.
#
# Inputs (environment): SUBSTITUTERS, KEYS, GITHUB_OUTPUT.
set -euo pipefail
here=$(dirname -- "${BASH_SOURCE[0]}")
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$here/lib.sh"

# Settings from the job environment would change what nix reports.
nix() {
  env -u NIX_CONFIG -u NIX_USER_CONF_FILES -u NIX_CONF_DIR -u NIX_REMOTE \
    "$(nix_bin)" "$@"
}
fail() {
  printf '::error::%s\n' "$1"
  exit 1
}

version=$(nix --version)
[[ $version == "nix (Nix) $NIX_VERSION" ]] ||
  fail "Installed '$version', expected Nix $NIX_VERSION."

nix store info >/dev/null || fail "The Nix daemon does not answer."

conf=$ROOT/etc/nix/nix.conf
expected=$("$here/nix-conf.sh")
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
