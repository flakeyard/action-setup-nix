# shellcheck shell=bash disable=SC2154,SC2034 # shared with tests/harness
# Each test runs a copy of the action whose file system root is a directory of
# the test, with stubs of curl and sudo and a fake release tarball whose
# installer only records what it got. Sourced by tests/run.sh.

# setup_action: setup of internal/testing with a fresh copy of the action, a
# clean runner and a fake tarball; the tests run the scripts of the copy.
setup_action() {
  setup
  action=$work/action fs=$work/root code_root=$work/action/scripts
  mkdir -p "$work/home" "$work/temp"
  : >"$work/path"
  copy_action
  make_clean_runner
  fake_tarball "$NIX_VERSION" x86_64-linux
  pin_tarball "$NIX_VERSION" x86_64-linux
  apply PATH="$root/tests/harness/stub:$sysbin" HOME="$work/home" \
    GITHUB_PATH="$work/path" RUNNER_TEMP="$work/temp" RUNNER_ARCH=X64 \
    SHELL_LIB="$shell_lib"
}

# copy_action: action.yml, the scripts and versions.sh in $action, which
# downloads from example.test and looks at $fs instead of the host.
copy_action() {
  mkdir -p "$action"
  cp -R "$root/action.yml" "$root/scripts" "$root/versions.sh" "$action/"
  sed -i -e "s|^NIX_BASE_URL=.*|NIX_BASE_URL=https://example.test/nix|" "$action/versions.sh"
  redirect_lib_paths
}

# redirect_lib_paths: ROOT of lib/env.sh to $fs; exits if lib/env.sh no
# longer has it. SYSTEM_PATH is the one of the copy of the library.
redirect_lib_paths() {
  local lib=$action/scripts/lib/env.sh
  sed -i -e "s|^ROOT=\$|ROOT=$fs|" "$lib"
  # Without it, the scripts would look at the host.
  if ! grep -qx "ROOT=$fs" "$lib"; then
    echo "tests/run.sh: cannot redirect ROOT in lib/env.sh" >&2
    exit 2
  fi
}

# make_clean_runner: $fs as a runner with systemd, Ubuntu 24.04 and no Nix.
make_clean_runner() {
  mkdir -p "$fs/run/systemd/system" "$fs/etc"
  printf 'ID=ubuntu\nVERSION_ID="24.04"\n' >"$fs/etc/os-release"
  printf 'root:x:0:\nrunner:x:1001:\n' >"$fs/etc/group"
}
