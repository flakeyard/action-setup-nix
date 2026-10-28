#!/usr/bin/env bash
# Unit tests of the scripts of the action. Each test runs a copy of the action
# whose file system root is a directory of the test, with stubs of curl and
# sudo and a fake release tarball whose installer only records what it got.
# Usage: tests/run.sh
set -uo pipefail
export LC_ALL=C

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
failed=0 passed=0 current=""
key=cache.example.org-1:$(printf 'k%.0s' {1..43})=

# The tools the scripts use, without a nix the host may have.
sysbin=$(mktemp -d)
trap 'rm -rf -- "$sysbin"' EXIT
for tool in bash env sed grep cat cp mv rm mkdir mktemp dirname id stat chmod \
  sha256sum tar xz cut ls touch; do
  ln -s "$(command -v "$tool")" "$sysbin/$tool"
done

# setup: a fresh copy of the action, a clean runner and a fake tarball.
setup() {
  work=$(mktemp -d)
  action=$work/action fs=$work/root
  mkdir -p "$action" "$fs/run/systemd/system" "$fs/etc" "$work/home" \
    "$work/fixtures" "$work/temp"
  cp -R "$root/scripts" "$root/versions.sh" "$action/"
  sed -i "s|^ROOT=\$|ROOT=$fs|" "$action/scripts/lib.sh"
  printf 'ID=ubuntu\nVERSION_ID="24.04"\n' >"$fs/etc/os-release"
  printf 'root:x:0:\nrunner:x:1001:\n' >"$fs/etc/group"
  fake_tarball 2.35.4 x86_64-linux
  sed -i -e "s|^NIX_BASE_URL=.*|NIX_BASE_URL=https://example.test/nix|" \
    -e "s|^NIX_SHA256_x86_64_linux=.*|NIX_SHA256_x86_64_linux=$(sha256sum <"$work/fixtures/nix-2.35.4-x86_64-linux.tar.xz" | cut -d' ' -f1)|" \
    "$action/versions.sh"
  : >"$work/calls"
  : >"$work/output"
  : >"$work/path"
  env_vars=(
    PATH="$root/tests/bin:$sysbin" HOME="$work/home"
    CALLS="$work/calls" FIXTURES="$work/fixtures"
    GITHUB_OUTPUT="$work/output" GITHUB_PATH="$work/path"
    RUNNER_TEMP="$work/temp" RUNNER_OS=Linux RUNNER_ARCH=X64
    RUNNER_ENVIRONMENT=github-hosted
  )
}

# fake_tarball VERSION SYSTEM [NIX_VERSION_OUTPUT]: a release tarball whose
# installer records its arguments and environment, writes nix.conf like the
# real one and installs a stub of nix.
fake_tarball() {
  local dir=$work/tarball/nix-$1-$2
  mkdir -p "$dir"
  cat >"$dir/install" <<EOF
#!/bin/bash
echo "install \$*" >>"$work/calls"
env >"$work/installer-env"
while ((\$#)); do
  [[ \$1 == --nix-extra-conf-file ]] && conf=\$2
  shift
done
mkdir -p "$fs/etc/nix" "$fs/nix/var/nix/profiles/default/bin"
{ cat "\$conf"; echo "build-users-group = nixbld"; } >"$fs/etc/nix/nix.conf"
cat >"$fs/nix/var/nix/profiles/default/bin/nix" <<'NIX'
#!/bin/bash
case "\$*" in
  --version) echo "nix (Nix) ${3:-$1}" ;;
  "store info") [[ ! -e "$work/daemon-down" ]] ;;
  "config show "*) sed -n "s/^\$3 = //p" "$fs/etc/nix/nix.conf" ;;
  *) exit 1 ;;
esac
NIX
chmod +x "$fs/nix/var/nix/profiles/default/bin/nix"
EOF
  chmod +x "$dir/install"
  tar --create --xz --file "$work/fixtures/nix-$1-$2.tar.xz" \
    --directory "$work/tarball" "nix-$1-$2"
}

# run NAME EXPECTED SCRIPT [VAR=VALUE...]: run a script of the action in the
# test environment; EXPECTED is ok or fail.
run() {
  local name=$1 expected=$2 script=$3 status=0
  shift 3
  env -i "${env_vars[@]}" "$@" "$action/scripts/$script" \
    >"$work/stdout" 2>"$work/stderr" || status=$?
  current=$name
  if [[ $expected == fail && $status -eq 0 ]] || [[ $expected == ok && $status -ne 0 ]]; then
    report "expected $expected, exit status $status: $(cat "$work/stdout" "$work/stderr")"
  fi
}

report() {
  [[ -n $current ]] || return 0
  echo "FAIL $current: $1"
  failed=$((failed + 1))
  current=""
}

# expect KIND [VALUE...]: check the last run.
expect() {
  [[ -n $current ]] || return 0
  case $1 in
    message) grep -qF -- "$2" "$work/stdout" "$work/stderr" || report "no message '$2' in: $(cat "$work/stdout" "$work/stderr")" ;;
    no-message) ! grep -qF -- "$2" "$work/stdout" "$work/stderr" || report "unexpected message '$2'" ;;
    errors)
      local count
      count=$(grep -c '^::error::' "$work/stdout")
      [[ $count == "$2" ]] || report "$count errors, expected $2: $(cat "$work/stdout")"
      ;;
    call) grep -qF -- "$2" "$work/calls" || report "no call '$2' in: $(paste -sd';' "$work/calls")" ;;
    no-call) ! grep -qF -- "$2" "$work/calls" || report "unexpected call '$2'" ;;
    output) grep -qxF -- "$2" "$work/output" || report "no output '$2' in: $(cat "$work/output")" ;;
    path) grep -qxF -- "$2" "$work/path" || report "no PATH entry '$2' in: $(cat "$work/path")" ;;
    file)
      [[ $(<"$2") == "$3" ]] || report "$2 is '$(<"$2")', expected '$3'"
      ;;
    mode)
      [[ $(stat -c %a "$2") == "$3" ]] || report "$2 has mode $(stat -c %a "$2"), expected $3"
      ;;
  esac
}

finish() {
  if [[ -n $current ]]; then
    passed=$((passed + 1))
  fi
  current=""
  rm -rf -- "$work"
}

# install: run check, install and the token step like the action does.
install() {
  run "$1 (install)" ok install.sh "${@:2}"
  current=""
}

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

# --- nix-conf.sh ------------------------------------------------------------

setup
run "nix-conf: defaults" ok nix-conf.sh
expect message "sandbox = true"
expect message "sandbox-fallback = false"
expect message "substituters = https://cache.nixos.org/"
expect message "accept-flake-config = false"
expect no-message "extra-substituters"
expect no-message "extra-trusted-public-keys"
finish

setup
run "nix-conf: extra caches on one line each" ok nix-conf.sh \
  SUBSTITUTERS=$'https://a.example.org\n https://b.example.org' KEYS="$key"
expect message "extra-substituters = https://a.example.org https://b.example.org"
expect message "extra-trusted-public-keys = $key"
finish

# --- install.sh -------------------------------------------------------------

setup
run "install: installs the pinned tarball" ok install.sh \
  NIX_USER_COUNT=1 NIX_CONFIG="sandbox = false" NIX_VERSION=9.9.9 \
  NIX_BASE_URL=https://evil.test
expect call "curl https://example.test/nix/nix-2.35.4/nix-2.35.4-x86_64-linux.tar.xz"
expect call "install --daemon --yes --no-channel-add --nix-extra-conf-file"
expect path "$fs/nix/var/nix/profiles/default/bin"
if [[ -n $current ]] && grep -qE '^(NIX_|CALLS|FIXTURES|GITHUB_)' "$work/installer-env"; then
  report "the installer got the job environment: $(grep -E '^(NIX_|CALLS|FIXTURES|GITHUB_)' "$work/installer-env")"
fi
expect file "$fs/etc/nix/nix.conf" "$("$action/scripts/nix-conf.sh")"$'\n'"build-users-group = nixbld"
[[ -z $current || -z $(ls -A "$work/temp") ]] || report "temporary files left: $(ls -A "$work/temp")"
finish

setup
fake_tarball 2.35.4 aarch64-linux
sed -i "s|^NIX_SHA256_aarch64_linux=.*|NIX_SHA256_aarch64_linux=$(sha256sum <"$work/fixtures/nix-2.35.4-aarch64-linux.tar.xz" | cut -d' ' -f1)|" \
  "$action/versions.sh"
run "install: arm64 tarball" ok install.sh RUNNER_ARCH=ARM64
expect call "curl https://example.test/nix/nix-2.35.4/nix-2.35.4-aarch64-linux.tar.xz"
finish

setup
echo tampered >>"$work/fixtures/nix-2.35.4-x86_64-linux.tar.xz"
run "install: hash mismatch installs nothing" fail install.sh
expect message "::error::SHA-256 of https://example.test/nix/nix-2.35.4/nix-2.35.4-x86_64-linux.tar.xz is"
expect no-call "install --daemon"
[[ -z $current || ! -e $fs/etc/nix ]] || report "nix.conf was written"
finish

setup
rm "$work/fixtures/nix-2.35.4-x86_64-linux.tar.xz"
run "install: download failure" fail install.sh
expect no-call "install --daemon"
finish

setup
run "install: extra caches reach nix.conf" ok install.sh \
  SUBSTITUTERS="https://cache.example.org" KEYS="$key"
expect file "$fs/etc/nix/nix.conf" "$(SUBSTITUTERS="https://cache.example.org" KEYS="$key" "$action/scripts/nix-conf.sh")"$'\n'"build-users-group = nixbld"
finish

# --- configure-token.sh -----------------------------------------------------

setup
run "token: written for the user only" ok configure-token.sh TOKEN=ghs_abc
expect file "$work/home/.config/nix/nix.conf" "access-tokens = github.com=ghs_abc"
expect mode "$work/home/.config/nix/nix.conf" 600
finish

setup
mkdir -p "$work/xdg"
run "token: XDG_CONFIG_HOME" ok configure-token.sh TOKEN=ghs_abc XDG_CONFIG_HOME="$work/xdg"
expect file "$work/xdg/nix/nix.conf" "access-tokens = github.com=ghs_abc"
finish

setup
mkdir -p "$work/home/.config/nix"
echo "accept-flake-config = true" >"$work/home/.config/nix/nix.conf"
run "token: does not overwrite a conf it did not write" fail configure-token.sh TOKEN=ghs_abc
expect file "$work/home/.config/nix/nix.conf" "accept-flake-config = true"
finish

# --- verify.sh --------------------------------------------------------------

setup
install "verify: ok"
run "verify: ok" ok verify.sh NIX_CONFIG="sandbox = false"
expect output "nix-version=2.35.4"
finish

setup
install "verify: extra caches" SUBSTITUTERS="https://cache.example.org" KEYS="$key"
run "verify: extra caches" ok verify.sh SUBSTITUTERS="https://cache.example.org" KEYS="$key"
finish

setup
install "verify: inputs differ from the installation" SUBSTITUTERS="https://cache.example.org" KEYS="$key"
run "verify: inputs differ from the installation" fail verify.sh
expect message "Unexpected line"
finish

setup
fake_tarball 2.35.4 x86_64-linux 2.34.0
sed -i "s|^NIX_SHA256_x86_64_linux=.*|NIX_SHA256_x86_64_linux=$(sha256sum <"$work/fixtures/nix-2.35.4-x86_64-linux.tar.xz" | cut -d' ' -f1)|" \
  "$action/versions.sh"
install "verify: wrong version"
run "verify: wrong version" fail verify.sh
expect message "Installed 'nix (Nix) 2.34.0', expected Nix 2.35.4"
finish

setup
install "verify: daemon down"
touch "$work/daemon-down"
run "verify: daemon down" fail verify.sh
expect message "The Nix daemon does not answer"
finish

setup
install "verify: extra line"
echo "trusted-users = runner" >>"$fs/etc/nix/nix.conf"
run "verify: extra line in nix.conf" fail verify.sh
expect message "Unexpected line in $fs/etc/nix/nix.conf: trusted-users = runner"
finish

setup
install "verify: sandbox off"
sed -i 's/^sandbox = true/sandbox = false/' "$fs/etc/nix/nix.conf"
run "verify: changed setting" fail verify.sh
expect message "does not start with the settings of this action"
finish

echo "passed: $passed, failed: $failed"
((failed == 0))
