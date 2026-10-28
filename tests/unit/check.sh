# shellcheck shell=bash disable=SC2154,SC2034 # shared with tests/lib.sh
# Unit tests of scripts/check.sh.

# --- check.sh: runner -------------------------------------------------------

setup
run "check: clean runner" ok check.sh
expect errors 0
expect no-message "::warning::"
finish

setup
run "check: arm64" ok check.sh RUNNER_ARCH=ARM64
finish

setup
run "check: macOS" fail check.sh RUNNER_OS=macOS RUNNER_ARCH=ARM64
expect message "Unsupported runner macOS/ARM64"
finish

setup
run "check: 32-bit runner" fail check.sh RUNNER_ARCH=X86
expect message "Unsupported runner Linux/X86"
finish

setup
run "check: self-hosted runner" fail check.sh RUNNER_ENVIRONMENT=self-hosted
expect message "Only GitHub-hosted runners"
finish

setup
touch "$fs/.dockerenv"
run "check: container job" fail check.sh
expect message "needs systemd"
finish

setup
rmdir "$fs/run/systemd/system"
run "check: no systemd" fail check.sh
expect message "needs systemd"
finish

setup
run "check: no passwordless sudo" fail check.sh SUDO_FAILS=1
expect message "passwordless sudo"
finish

setup
printf 'ID=ubuntu\nVERSION_ID="26.04"\n' >"$fs/etc/os-release"
run "check: untested Ubuntu warns" ok check.sh
expect message "::warning::This action is not tested on ubuntu/26.04"
finish

# --- check.sh: Nix installed before -----------------------------------------

setup
mkdir "$fs/nix"
run "check: /nix exists" fail check.sh
expect message "found: /nix"
finish

setup
mkdir "$fs/etc/nix"
run "check: /etc/nix exists" fail check.sh
expect message "found: /etc/nix"
finish

setup
echo "nixbld:x:30000:" >>"$fs/etc/group"
run "check: group nixbld exists" fail check.sh
expect message "found: group nixbld"
finish

setup
mkdir -p "$work/home/.config/nix"
touch "$work/home/.config/nix/nix.conf"
run "check: user nix.conf exists" fail check.sh
expect message "found: $work/home/.config/nix/nix.conf"
finish

setup
mkdir -p "$work/xdg/nix" "$work/bin"
touch "$work/xdg/nix/nix.conf"
printf '#!/bin/sh\n' >"$work/bin/nix"
chmod +x "$work/bin/nix"
run "check: nix on PATH and XDG_CONFIG_HOME conf" fail check.sh \
  XDG_CONFIG_HOME="$work/xdg" PATH="$work/bin:$root/tests/bin:$sysbin"
expect message "found: nix on PATH $work/xdg/nix/nix.conf"
finish

# --- check.sh: inputs -------------------------------------------------------

setup
run "check: substituter and key" ok check.sh \
  SUBSTITUTERS="https://cache.example.org" KEYS="$key"
expect errors 0
expect no-message "::notice::"
finish

setup
run "check: several, separated by newlines and spaces" ok check.sh \
  SUBSTITUTERS=$'https://a.example.org/\n  https://b.example.org:8443/x/y_z~1  ' \
  KEYS=$'\n'"$key $key"$'\n'
expect errors 0
finish

setup
run "check: substituter without key gives a notice" ok check.sh \
  SUBSTITUTERS="https://mirror.example.org/nix-channels/store"
expect message "::notice::Extra substituters without extra keys"
finish

setup
run "check: key without substituter" fail check.sh KEYS="$key"
expect message "extra-trusted-public-keys is set without extra-substituters"
finish

for url in "http://cache.example.org" "https://cache.example.org?trusted=1" \
  "https://cache.example.org/?priority=10" "https://cache.example.org#x" \
  "https://user:pw@cache.example.org" "s3://bucket" "https://" \
  "https://cache.example.org/a%20b" "file:///nix/store"; do
  setup
  run "check: rejects substituter $url" fail check.sh SUBSTITUTERS="$url" KEYS="$key"
  expect message "Invalid extra substituter '$url'"
  finish
done

setup
run "check: newline cannot add a setting" fail check.sh \
  SUBSTITUTERS=$'https://cache.example.org\nrequire-sigs = false' KEYS="$key"
expect message "Invalid extra substituter 'require-sigs'"
expect message "Invalid extra substituter '='"
finish

for bad in "cache.example.org-1:short=" "no-colon" "a:$(printf 'k%.0s' {1..43})" \
  "a b:$(printf 'k%.0s' {1..43})=" "x:$(printf 'k%.0s' {1..43})=#"; do
  setup
  run "check: rejects key $bad" fail check.sh SUBSTITUTERS=https://c.example.org KEYS="$bad"
  expect message "Invalid extra trusted public key"
  finish
done

setup
run "check: masks a valid token" ok check.sh TOKEN=ghs_abcDEF123
expect message "::add-mask::ghs_abcDEF123"
finish

setup
run "check: token with dots and hyphens, like installation tokens" ok check.sh TOKEN=ghs_aB1.c-D_2.e3
expect message "::add-mask::ghs_aB1.c-D_2.e3"
finish

for bad in "ghs abc" "ghs_abc#x" "ghs_a=b"; do
  setup
  run "check: rejects token '$bad'" fail check.sh TOKEN="$bad"
  expect message "Invalid github-token"
  finish
done

setup
run "check: token with a newline" fail check.sh TOKEN=$'ghs_abc\naccept-flake-config = true'
expect message "Invalid github-token"
expect no-message "ghs_abc"
expect no-message "::add-mask::"
finish

setup
mkdir "$fs/nix"
run "check: reports every problem at once" fail check.sh \
  RUNNER_ENVIRONMENT=self-hosted SUBSTITUTERS=http://x KEYS=bad TOKEN="a b"
expect errors 5
finish

# --- check.sh: more ---------------------------------------------------------

setup
run "check: carriage return cannot start a workflow command" fail check.sh \
  SUBSTITUTERS=$'x\r::stop-commands::k' KEYS="$key"
expect message "Invalid extra substituter 'x'"
expect message "Invalid extra substituter '::stop-commands::k'"
[[ -z $current ]] || ! grep -q $'\r' "$work/stdout" || report "a carriage return was printed"
finish

setup
run "check: other control characters are not printed" fail check.sh \
  SUBSTITUTERS=$'https://a\x1b]8;;x' KEYS="$key"
expect message "Invalid extra substituter 'https://a?]8;;x'"
finish

for leftover in etc/xdg/nix etc/systemd/system/nix-daemon.service etc/bashrc.backup-before-nix; do
  setup
  mkdir -p "$fs/$(dirname "$leftover")"
  touch "$fs/$leftover"
  run "check: finds /$leftover" fail check.sh
  expect message "found: /$leftover"
  finish
done
