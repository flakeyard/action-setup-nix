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

# shellcheck source-path=SCRIPTDIR source=../versions.sh
source "$root/versions.sh"

# The tools the scripts use, without a nix the host may have.
sysbin=$(mktemp -d)
trap 'rm -rf -- "$sysbin"' EXIT
for tool in bash env sed grep cat cp mv rm mkdir mktemp dirname id stat chmod \
  sha256sum tar xz cut ls touch python3 openssl base64 sort cmp diff; do
  ln -s "$(command -v "$tool")" "$sysbin/$tool"
done

# setup: a fresh copy of the action, a clean runner and a fake tarball.
setup() {
  work=$(mktemp -d)
  action=$work/action fs=$work/root
  mkdir -p "$action" "$fs/run/systemd/system" "$fs/etc" "$work/home" \
    "$work/fixtures" "$work/temp"
  cp -R "$root/scripts" "$root/versions.sh" "$action/"
  sed -i -e "s|^ROOT=\$|ROOT=$fs|" \
    -e "s|^SYSTEM_PATH=.*|SYSTEM_PATH=$root/tests/bin:$sysbin|" "$action/scripts/lib.sh"
  # Without these, the scripts would look at the host.
  if ! grep -qx "ROOT=$fs" "$action/scripts/lib.sh" ||
    ! grep -qx "SYSTEM_PATH=$root/tests/bin:$sysbin" "$action/scripts/lib.sh"; then
    echo "tests/run.sh: cannot redirect ROOT and SYSTEM_PATH in lib.sh" >&2
    exit 2
  fi
  printf 'ID=ubuntu\nVERSION_ID="24.04"\n' >"$fs/etc/os-release"
  printf 'root:x:0:\nrunner:x:1001:\n' >"$fs/etc/group"
  fake_tarball "$NIX_VERSION" x86_64-linux
  sed -i -e "s|^NIX_BASE_URL=.*|NIX_BASE_URL=https://example.test/nix|" \
    -e "s|^NIX_SHA256_x86_64_linux=.*|NIX_SHA256_x86_64_linux=$(sha256sum <"$work/fixtures/nix-$NIX_VERSION-x86_64-linux.tar.xz" | cut -d' ' -f1)|" \
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

# run NAME EXPECTED SCRIPT [VAR=VALUE...] [-- ARG...]: run a script of the
# action in the test environment; EXPECTED is ok or fail.
run() {
  local name=$1 expected=$2 script=$3 status=0 vars=() args=()
  shift 3
  while (($#)) && [[ $1 != -- ]]; do
    vars+=("$1")
    shift
  done
  (($#)) && shift && args=("$@")
  env -i "${env_vars[@]}" "${vars[@]}" "$action/scripts/$script" "${args[@]}" \
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

# install NAME [VAR=VALUE...]: install and store a token like the action does.
install() {
  run "$1 (install)" ok install.sh "${@:2}"
  run "$1 (token)" ok configure-token.sh TOKEN=ghs_abc
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
expect call "curl https://example.test/nix/nix-$NIX_VERSION/nix-$NIX_VERSION-x86_64-linux.tar.xz"
expect call "install --daemon --yes --no-channel-add --nix-extra-conf-file"
expect path "$fs/nix/var/nix/profiles/default/bin"
if [[ -n $current ]] && grep -qE '^(NIX_|CALLS|FIXTURES|GITHUB_)' "$work/installer-env"; then
  report "the installer got the job environment: $(grep -E '^(NIX_|CALLS|FIXTURES|GITHUB_)' "$work/installer-env")"
fi
expect file "$fs/etc/nix/nix.conf" "$("$action/scripts/nix-conf.sh")"$'\n'"build-users-group = nixbld"
[[ -z $current || -z $(ls -A "$work/temp") ]] || report "temporary files left: $(ls -A "$work/temp")"
finish

setup
fake_tarball "$NIX_VERSION" aarch64-linux
sed -i "s|^NIX_SHA256_aarch64_linux=.*|NIX_SHA256_aarch64_linux=$(sha256sum <"$work/fixtures/nix-$NIX_VERSION-aarch64-linux.tar.xz" | cut -d' ' -f1)|" \
  "$action/versions.sh"
run "install: arm64 tarball" ok install.sh RUNNER_ARCH=ARM64
expect call "curl https://example.test/nix/nix-$NIX_VERSION/nix-$NIX_VERSION-aarch64-linux.tar.xz"
finish

setup
echo tampered >>"$work/fixtures/nix-$NIX_VERSION-x86_64-linux.tar.xz"
run "install: hash mismatch installs nothing" fail install.sh
expect message "::error::SHA-256 of https://example.test/nix/nix-$NIX_VERSION/nix-$NIX_VERSION-x86_64-linux.tar.xz is"
expect no-call "install --daemon"
[[ -z $current || ! -e $fs/etc/nix ]] || report "nix.conf was written"
finish

setup
rm "$work/fixtures/nix-$NIX_VERSION-x86_64-linux.tar.xz"
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
expect output "nix-version=$NIX_VERSION"
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
fake_tarball "$NIX_VERSION" x86_64-linux 0.0.1
sed -i "s|^NIX_SHA256_x86_64_linux=.*|NIX_SHA256_x86_64_linux=$(sha256sum <"$work/fixtures/nix-$NIX_VERSION-x86_64-linux.tar.xz" | cut -d' ' -f1)|" \
  "$action/versions.sh"
install "verify: wrong version"
run "verify: wrong version" fail verify.sh
expect message "Installed 'nix (Nix) 0.0.1', expected Nix $NIX_VERSION"
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

# --- install.sh and verify.sh: more -------------------------------------------

setup
sed -i 's|^#!/bin/bash$|#!/bin/bash\nexit 3|' "$work/tarball/nix-$NIX_VERSION-x86_64-linux/install"
tar --create --xz --file "$work/fixtures/nix-$NIX_VERSION-x86_64-linux.tar.xz" \
  --directory "$work/tarball" "nix-$NIX_VERSION-x86_64-linux"
sed -i "s|^NIX_SHA256_x86_64_linux=.*|NIX_SHA256_x86_64_linux=$(sha256sum <"$work/fixtures/nix-$NIX_VERSION-x86_64-linux.tar.xz" | cut -d' ' -f1)|" \
  "$action/versions.sh"
run "install: installer failure" fail install.sh
expect message "::error::The Nix installer failed"
[[ -z $current || ! -s $work/path ]] || report "PATH was extended: $(cat "$work/path")"
[[ -z $current || -z $(ls -A "$work/temp") ]] || report "temporary files left"
finish

setup
run "verify: nothing installed" fail verify.sh
expect message "::error::$fs/nix/var/nix/profiles/default/bin/nix was not installed."
finish

setup
install "verify: no nix.conf"
rm "$fs/etc/nix/nix.conf"
run "verify: no nix.conf" fail verify.sh
expect message "::error::$fs/etc/nix/nix.conf was not installed."
finish

# --- check-tarball.sh ---------------------------------------------------------

# A key of a test cache, and names of two store paths.
signing_key=$sysbin/../signing.pem
openssl genpkey -algorithm ed25519 -out "$signing_key" 2>/dev/null
test_key=test-1:$(openssl pkey -in "$signing_key" -pubout -outform DER | tail -c 32 | base64)
dep=$(printf 'a%.0s' {1..32})-dep-1.0
nix=$(printf 'b%.0s' {1..32})-nix-9.0.0

# release_setup: a release tarball whose store paths are in the test cache.
# Change $release, then call pack.
release_setup() {
  setup
  sed -i -e "s|^cache=.*|cache=https://example.test/cache|" \
    -e "s|^key=.*|key=$test_key|" "$action/scripts/check-tarball.sh"
  release=$work/release/nix-9.0.0-x86_64-linux
  mkdir -p "$release/store/$dep/lib" "$release/store/$nix/bin"
  echo library >"$release/store/$dep/lib/libdep"
  printf '#!/bin/sh\n' >"$release/store/$nix/bin/nix"
  chmod +x "$release/store/$nix/bin/nix"
  ln -s nix "$release/store/$nix/bin/nix-store"
  echo installer >"$release/install"
  reginfo_entry "$dep" >"$release/.reginfo"
  reginfo_entry "$nix" "$dep" >>"$release/.reginfo"
  narinfo "$dep"
  narinfo "$nix" "$dep"
}

# reginfo_entry NAME [REFERENCE...]: the .reginfo lines of a store path.
reginfo_entry() {
  local name=$1
  shift
  printf '/nix/store/%s\n' "$name"
  "$root/scripts/nar-hash.py" "$release/store/$name" | tr ' ' '\n'
  printf '\n%s\n' "$#"
  (($#)) && printf '/nix/store/%s\n' "$@"
  return 0
}

# narinfo NAME [REFERENCE...]: a signed narinfo of a store path in the cache.
narinfo() {
  local name=$1 hash size fingerprint refs
  shift
  read -r hash size < <("$root/scripts/nar-hash.py" "$release/store/$name")
  refs=""
  (($#)) && refs=$(printf '/nix/store/%s,' "$@")
  fingerprint="1;/nix/store/$name;$hash;$size;${refs%,}"
  printf '%s' "$fingerprint" >"$work/fingerprint"
  openssl pkeyutl -sign -inkey "${sign_with:-$signing_key}" -rawin \
    -in "$work/fingerprint" -out "$work/sig"
  {
    echo "StorePath: /nix/store/$name"
    echo "NarHash: $hash"
    echo "NarSize: $size"
    echo "References: $*"
    echo "Sig: ${test_key%%:*}:$(base64 -w0 <"$work/sig")"
  } >"$work/fixtures/${name%%-*}.narinfo"
}

pack() {
  tar --create --xz --file "$work/release.tar.xz" --directory "$work/release" .
}

release_setup
pack
run "check-tarball: genuine release" ok check-tarball.sh -- "$work/release.tar.xz"
expect message "2 store paths match https://example.test/cache and its signatures."
finish

release_setup
echo changed >>"$release/store/$nix/bin/nix"
pack
run "check-tarball: changed contents" fail check-tarball.sh -- "$work/release.tar.xz"
expect message "error: the contents of /nix/store/$nix do not match .reginfo"
finish

release_setup
mkdir "$release/store/$(printf 'c%.0s' {1..32})-extra"
pack
run "check-tarball: unlisted store path" fail check-tarball.sh -- "$work/release.tar.xz"
expect message "is not listed in .reginfo"
finish

release_setup
reginfo_entry "$dep" >"$release/.reginfo"
reginfo_entry "$nix" "$nix" >>"$release/.reginfo"
pack
run "check-tarball: references differ from the cache" fail check-tarball.sh -- "$work/release.tar.xz"
expect message "error: /nix/store/$nix in the tarball differs from https://example.test/cache"
finish

release_setup
rm "$work/fixtures/${nix%%-*}.narinfo"
pack
run "check-tarball: not in the cache" fail check-tarball.sh -- "$work/release.tar.xz"
expect message "returned HTTP 404 for /nix/store/$nix"
finish

release_setup
openssl genpkey -algorithm ed25519 -out "$work/other.pem" 2>/dev/null
sign_with=$work/other.pem narinfo "$nix" "$dep"
pack
run "check-tarball: signed by another key" fail check-tarball.sh -- "$work/release.tar.xz"
expect message "error: no valid signature of test-1 for /nix/store/$nix"
finish

release_setup
printf '/nix/store/%s\nsha256:%s\n1\n\n%s\n' "$dep" "$(printf '0%.0s' {1..52})" \
  "checked[\$(touch $work/PWNED)]" >"$release/.reginfo"
pack
run "check-tarball: no code from .reginfo" fail check-tarball.sh -- "$work/release.tar.xz"
expect message "invalid size or reference count"
[[ -z $current || ! -e $work/PWNED ]] || report "code from .reginfo ran"
finish

release_setup
printf '/nix/store/../../x\nsha256:%s\n1\n\n0\n' "$(printf '0%.0s' {1..52})" >"$release/.reginfo"
pack
run "check-tarball: no paths outside the store" fail check-tarball.sh -- "$work/release.tar.xz"
expect message "invalid store path in .reginfo: /nix/store/../../x"
finish

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
  cp "$action/versions.sh" "$work/versions.before"
}

update_setup
run "update-nix: pins a new version" ok update-nix.sh -- 9.0.0
expect message "Changes of the installer scripts for aarch64-linux since $NIX_VERSION:"
expect file "$action/versions.sh" "$(sed -e "s/^NIX_VERSION=.*/NIX_VERSION=9.0.0/" \
  -e "s/^NIX_SHA256_x86_64_linux=.*/NIX_SHA256_x86_64_linux=$(cat "$work/fixtures/nix-9.0.0-x86_64-linux.tar.xz.sha256")/" \
  -e "s/^NIX_SHA256_aarch64_linux=.*/NIX_SHA256_aarch64_linux=$(cat "$work/fixtures/nix-9.0.0-aarch64-linux.tar.xz.sha256")/" \
  "$work/versions.before")"
finish

update_setup
run "update-nix: a failing system changes nothing" fail update-nix.sh FAIL_SYSTEMS=aarch64-linux -- 9.0.0
expect file "$action/versions.sh" "$(cat "$work/versions.before")"
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

echo "passed: $passed, failed: $failed"
((failed == 0))
