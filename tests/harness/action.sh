# shellcheck shell=bash disable=SC2154,SC2034 # shared with tests/harness
# Each test runs a copy of the action whose file system root is a directory of
# the test, with stubs of curl and sudo and a fake release tarball whose
# installer only records what it got. Sourced by tests/run.sh.

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
    PATH="$root/tests/harness/stub:$sysbin" HOME="$work/home"
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

# redirect_lib_paths: ROOT and SYSTEM_PATH of lib/env.sh to $fs and the tools
# of the tests; exits if lib/env.sh no longer has them.
redirect_lib_paths() {
  local lib=$action/scripts/lib/env.sh system_path=$root/tests/harness/stub:$sysbin
  sed -i -e "s|^ROOT=\$|ROOT=$fs|" -e "s|^SYSTEM_PATH=.*|SYSTEM_PATH=$system_path|" "$lib"
  # Without these, the scripts would look at the host.
  if ! grep -qx "ROOT=$fs" "$lib" || ! grep -qx "SYSTEM_PATH=$system_path" "$lib"; then
    echo "tests/run.sh: cannot redirect ROOT and SYSTEM_PATH in lib/env.sh" >&2
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

# github_setup: setup, with the scripts of .github/scripts in
# $action/scripts/github.
github_setup() {
  setup
  cp -R "$root/.github/scripts" "$action/scripts/github"
}
