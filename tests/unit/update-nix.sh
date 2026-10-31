# shellcheck shell=bash disable=SC2154,SC2034 # shared with tests/lib.sh
# Unit tests of scripts/update/nix.sh.

# --- update-nix.sh ------------------------------------------------------------

# publish_hash VERSION SYSTEM: publishes the SHA-256 of a release tarball next
# to it, like releases.nixos.org.
publish_hash() {
  local tarball
  tarball=$(tarball_fixture "$@")
  sha256_of "$tarball" >"$tarball.sha256"
}

# update_setup: releases $NIX_VERSION (pinned) and 9.0.0 of both systems, and a
# check-tarball.py that fails for the systems in $FAIL_SYSTEMS.
update_setup() {
  setup
  local system
  fake_tarball "$NIX_VERSION" aarch64-linux
  pin_tarball "$NIX_VERSION" aarch64-linux
  for system in x86_64-linux aarch64-linux; do
    fake_tarball 9.0.0 "$system"
    publish_hash "$NIX_VERSION" "$system"
    publish_hash 9.0.0 "$system"
  done
  cat >"$action/scripts/update/check-tarball.py" <<'EOF2'
#!/usr/bin/env bash
for system in ${FAIL_SYSTEMS-}; do
  [[ $1 != *"$system"* ]] || exit 1
done
EOF2
  cp "$root/README.md" "$action/README.md"
  cp "$action/versions.sh" "$work/versions.before"
}

update_setup
run "update-nix: pins a new version" ok update/nix.sh -- 9.0.0
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
run "update-nix: a failing system changes nothing" fail update/nix.sh FAIL_SYSTEMS=aarch64-linux -- 9.0.0
expect file "$action/versions.sh" "$(cat "$work/versions.before")"
expect file "$action/README.md" "$(cat "$root/README.md")"
finish

update_setup
echo 0000 >"$work/fixtures/nix-9.0.0-aarch64-linux.tar.xz.sha256"
run "update-nix: published hash differs" fail update/nix.sh -- 9.0.0
expect message "published 0000"
expect file "$action/versions.sh" "$(cat "$work/versions.before")"
finish

update_setup
run "update-nix: the pinned version checks the pin" ok update/nix.sh -- "$NIX_VERSION"
expect message "versions.sh already pins Nix $NIX_VERSION with these hashes."
expect file "$action/versions.sh" "$(cat "$work/versions.before")"
finish

update_setup
sed -i "s|^NIX_SHA256_aarch64_linux=.*|NIX_SHA256_aarch64_linux=0000|" "$action/versions.sh"
run "update-nix: a wrong pin is corrected" ok update/nix.sh -- "$NIX_VERSION"
expect message "Pinned Nix $NIX_VERSION."
finish

update_setup
echo tampered >>"$work/fixtures/nix-$NIX_VERSION-aarch64-linux.tar.xz"
run "update-nix: the pinned release is checked before the diff" fail update/nix.sh -- 9.0.0
expect message "error: the pinned tarball for aarch64-linux has SHA-256"
expect no-message "Changes of the installer scripts for aarch64-linux"
expect file "$action/versions.sh" "$(cat "$work/versions.before")"
finish

update_setup
mkdir -p "$work/tarball/nix-9.0.0-x86_64-linux/doc"
echo "new installer file" >"$work/tarball/nix-9.0.0-x86_64-linux/doc/store"
repack_tarball 9.0.0 x86_64-linux
publish_hash 9.0.0 x86_64-linux
run "update-nix: shows new files, also those named store" ok update/nix.sh -- 9.0.0
expect message "+new installer file"
finish

if ((EUID != 0)); then
  update_setup
  # A file that diff cannot read: added to the tarball with mode 000.
  echo secret >"$work/unreadable"
  tar --create --file "$work/new.tar" --directory "$work/tarball" nix-9.0.0-x86_64-linux
  tar --append --file "$work/new.tar" --directory "$work" --mode=000 \
    --transform 's|^|nix-9.0.0-x86_64-linux/|' unreadable
  xz --stdout "$work/new.tar" >"$(tarball_fixture 9.0.0 x86_64-linux)"
  publish_hash 9.0.0 x86_64-linux
  run "update-nix: an error of diff fails" fail update/nix.sh -- 9.0.0
  expect message "error: cannot compare the installer scripts for x86_64-linux"
  expect file "$action/versions.sh" "$(cat "$work/versions.before")"
  finish
fi

update_setup
rm "$work/fixtures/nix-9.0.0-aarch64-linux.tar.xz"
run "update-nix: a failed download stops" fail update/nix.sh -- 9.0.0
expect message "curl: (22)"
expect no-message "No such file"
finish
