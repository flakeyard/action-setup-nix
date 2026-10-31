#!/usr/bin/env bash
# Checks an installation in a job whose environment tries to change it:
# BASH_ENV, exported functions, SHELLOPTS with PS4, fake tools first on PATH
# and NIX_* variables of the installer.
set -euo pipefail
fail() {
  printf '::error::%s\n' "$1"
  exit 1
}
for marker in bash-env-ran functions-ran ps4-ran fake-tools-ran; do
  if [[ -e $RUNNER_TEMP/$marker ]]; then
    fail "The action used the job environment ($marker): $(<"$RUNNER_TEMP/$marker")"
  fi
done
group=$(getent group nixbld) || fail "No group nixbld."
IFS=: read -r _ _ gid members <<<"$group"
IFS=, read -r -a users <<<"$members"
[[ $gid == 30000 && ${#users[@]} == 32 ]] ||
  fail "The installer took NIX_BUILD_GROUP_ID or NIX_USER_COUNT: GID $gid, ${#users[@]} build users."
grep -qx 'sandbox = true' /etc/nix/nix.conf || fail "NIX_CONFIG reached /etc/nix/nix.conf."
echo "The job environment did not change the installation."
