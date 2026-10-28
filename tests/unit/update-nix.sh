# shellcheck shell=bash disable=SC2154,SC2034 # shared with tests/lib.sh
# Unit tests of scripts/update-nix.sh.

# --- update-nix.sh ------------------------------------------------------------

# update_setup: releases $NIX_VERSION (pinned) and 9.0.0 of both systems, and a
# check-tarball.sh that fails for the systems in $FAIL_SYSTEMS.
update_setup() {
  setup
  local system file
  fake_tarball "$NIX_VERSION" aarch64-linux
  sed -i "s|^NIX_SHA256_aarch64_linux=.*|NIX_SHA256_aarch64_linux=$(sha256sum <"$work/fixtures/nix-$NIX_VERSION-aarch64-linux.tar.xz" | cut -d' ' -f1)|" \
    "$action/versions.sh"
  for system in x86_64-linux aarch64-linux; do
    fake_tarball 9.0.0 "$system"
    for file in "$work"/fixtures/nix-{"$NIX_VERSION",9.0.0}-"$system".tar.xz; do
      sha256sum <"$file" | cut -d' ' -f1 >"$file.sha256"
    done
  done
  cat >"$action/scripts/check-tarball.sh" <<'EOF2'
#!/usr/bin/env bash
for system in ${FAIL_SYSTEMS-}; do
  [[ $1 != *"$system"* ]] || exit 1
done
EOF2
  cp "$root/README.md" "$action/README.md"
  cp "$action/versions.sh" "$work/versions.before"
}

update_setup
run "update-nix: pins a new version" ok update-nix.sh -- 9.0.0
expect message "Changes of the installer scripts for aarch64-linux since $NIX_VERSION:"
expect message "/new/nix-9.0.0-aarch64-linux/install"
[[ -z $current ]] || grep -qx "  against the SHA-256 recorded in the action. This release installs Nix 9.0.0." "$action/README.md" ||
  report "the README does not name Nix 9.0.0: $(grep 'This release installs' "$action/README.md")"
expect file "$action/versions.sh" "$(sed -e "s/^NIX_VERSION=.*/NIX_VERSION=9.0.0/" \
  -e "s/^NIX_SHA256_x86_64_linux=.*/NIX_SHA256_x86_64_linux=$(cat "$work/fixtures/nix-9.0.0-x86_64-linux.tar.xz.sha256")/" \
  -e "s/^NIX_SHA256_aarch64_linux=.*/NIX_SHA256_aarch64_linux=$(cat "$work/fixtures/nix-9.0.0-aarch64-linux.tar.xz.sha256")/" \
  "$work/versions.before")"
finish

update_setup
run "update-nix: a failing system changes nothing" fail update-nix.sh FAIL_SYSTEMS=aarch64-linux -- 9.0.0
expect file "$action/versions.sh" "$(cat "$work/versions.before")"
expect file "$action/README.md" "$(cat "$root/README.md")"
finish

update_setup
echo 0000 >"$work/fixtures/nix-9.0.0-aarch64-linux.tar.xz.sha256"
run "update-nix: published hash differs" fail update-nix.sh -- 9.0.0
expect message "published 0000"
expect file "$action/versions.sh" "$(cat "$work/versions.before")"
finish

update_setup
run "update-nix: the pinned version checks the pin" ok update-nix.sh -- "$NIX_VERSION"
expect message "versions.sh already pins Nix $NIX_VERSION with these hashes."
expect file "$action/versions.sh" "$(cat "$work/versions.before")"
finish

update_setup
sed -i "s|^NIX_SHA256_aarch64_linux=.*|NIX_SHA256_aarch64_linux=0000|" "$action/versions.sh"
run "update-nix: a wrong pin is corrected" ok update-nix.sh -- "$NIX_VERSION"
expect message "Pinned Nix $NIX_VERSION."
finish
