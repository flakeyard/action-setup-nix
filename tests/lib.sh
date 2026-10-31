# shellcheck shell=bash disable=SC2034 # variables for the unit tests
# Harness of the unit tests, sourced by tests/run.sh. Each test runs a copy of
# the action whose file system root is a directory of the test, with stubs of
# curl and sudo and a fake release tarball whose installer only records what it
# got.
export LC_ALL=C

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
failed=0 passed=0 current=""
key=cache.example.org-1:$(printf 'k%.0s' {1..43})=

# shellcheck source-path=SCRIPTDIR source=../versions.sh
source "$root/versions.sh"

# Files shared by all tests, removed at the end.
shared=$(mktemp -d)
trap 'rm -rf -- "$shared"' EXIT

# The tools the scripts use, without a nix the host may have.
sysbin=$shared/bin
mkdir "$sysbin"
for tool in bash env sed grep cat cp mv rm mkdir mktemp dirname id stat chmod \
  sha256sum tar xz cut ls touch python3 openssl base64 sort cmp diff jq paste; do
  ln -s "$(command -v "$tool")" "$sysbin/$tool"
done

# setup: a fresh copy of the action, a clean runner and a fake tarball.
setup() {
  work=$(mktemp -d)
  action=$work/action fs=$work/root
  mkdir -p "$work/home" "$work/fixtures" "$work/temp"
  copy_action
  make_clean_runner
  fake_tarball "$NIX_VERSION" x86_64-linux
  pin_tarball "$NIX_VERSION" x86_64-linux
  reset_records
  env_vars=(
    PATH="$root/tests/bin:$sysbin" HOME="$work/home"
    CALLS="$work/calls" FIXTURES="$work/fixtures"
    GITHUB_OUTPUT="$work/output" GITHUB_PATH="$work/path"
    RUNNER_TEMP="$work/temp" RUNNER_OS=Linux RUNNER_ARCH=X64
    RUNNER_ENVIRONMENT=github-hosted
  )
}

# copy_action: the scripts and versions.sh in $action, which downloads from
# example.test and looks at $fs instead of the host.
copy_action() {
  mkdir -p "$action"
  cp -R "$root/scripts" "$root/versions.sh" "$action/"
  sed -i -e "s|^NIX_BASE_URL=.*|NIX_BASE_URL=https://example.test/nix|" "$action/versions.sh"
  redirect_lib_paths
}

# redirect_lib_paths: ROOT and SYSTEM_PATH of lib.sh to $fs and the tools of
# the tests; exits if lib.sh no longer has them.
redirect_lib_paths() {
  local lib=$action/scripts/lib.sh system_path=$root/tests/bin:$sysbin
  sed -i -e "s|^ROOT=\$|ROOT=$fs|" -e "s|^SYSTEM_PATH=.*|SYSTEM_PATH=$system_path|" "$lib"
  # Without these, the scripts would look at the host.
  if ! grep -qx "ROOT=$fs" "$lib" || ! grep -qx "SYSTEM_PATH=$system_path" "$lib"; then
    echo "tests/run.sh: cannot redirect ROOT and SYSTEM_PATH in lib.sh" >&2
    exit 2
  fi
}

# make_clean_runner: $fs as a runner with systemd, Ubuntu 24.04 and no Nix.
make_clean_runner() {
  mkdir -p "$fs/run/systemd/system" "$fs/etc"
  printf 'ID=ubuntu\nVERSION_ID="24.04"\n' >"$fs/etc/os-release"
  printf 'root:x:0:\nrunner:x:1001:\n' >"$fs/etc/group"
}

# reset_records: empty files for the calls of the stubs and for GITHUB_OUTPUT
# and GITHUB_PATH.
reset_records() {
  : >"$work/calls"
  : >"$work/output"
  : >"$work/path"
}

# tarball_fixture VERSION SYSTEM: prints the path of a release tarball that the
# curl stub serves.
tarball_fixture() {
  local version=$1 system=$2
  echo "$work/fixtures/nix-$version-$system.tar.xz"
}

# sha256_of FILE: prints the SHA-256 of FILE.
sha256_of() {
  sha256sum <"$1" | cut -d' ' -f1
}

# pin_tarball VERSION SYSTEM: pins the hash of the release tarball of SYSTEM
# in the copy of the action.
pin_tarball() {
  local version=$1 system=$2 var=NIX_SHA256_${2//-/_} hash
  hash=$(sha256_of "$(tarball_fixture "$version" "$system")")
  sed -i -e "s|^$var=.*|$var=$hash|" "$action/versions.sh"
}

# repack_tarball VERSION SYSTEM: packs $work/tarball/nix-VERSION-SYSTEM again
# into the release tarball, after a change.
repack_tarball() {
  local version=$1 system=$2
  tar --create --xz --file "$(tarball_fixture "$version" "$system")" \
    --directory "$work/tarball" "nix-$version-$system"
}

# fake_tarball VERSION SYSTEM [NIX_VERSION_OUTPUT]: a release tarball whose
# installer records its arguments and environment, writes nix.conf like the
# real one and installs a stub of nix.
fake_tarball() {
  local version=$1 system=$2 reported=${3:-$1}
  local dir=$work/tarball/nix-$version-$system
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
  --version) echo "nix (Nix) $reported" ;;
  "store info") [[ ! -e "$work/daemon-down" ]] ;;
  "config show "*) sed -n "s/^\$3 = //p" "$fs/etc/nix/nix.conf" ;;
  *) exit 1 ;;
esac
NIX
chmod +x "$fs/nix/var/nix/profiles/default/bin/nix"
EOF
  chmod +x "$dir/install"
  repack_tarball "$version" "$system"
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
