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

# The tools the scripts use, without a nix the host may have.
sysbin=$(mktemp -d)
trap 'rm -rf -- "$sysbin"' EXIT
for tool in bash env sed grep cat cp mv rm mkdir mktemp dirname id stat chmod \
  sha256sum tar xz cut ls touch python3 openssl base64 sort cmp diff jq paste; do
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
