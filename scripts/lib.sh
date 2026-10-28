# shellcheck shell=bash
# Shared by the scripts of the action; sourced, not run.

# Root of the file system. Only the tests change it, in their own copy of the
# action; nothing at run time can.
ROOT=

export LC_ALL=C

ACTION_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source-path=SCRIPTDIR source=../versions.sh
source "$ACTION_DIR/versions.sh"

# nix_system: prints the Nix system of the runner; fails on other runners.
nix_system() {
  case ${RUNNER_ARCH-} in
    X64) echo x86_64-linux ;;
    ARM64) echo aarch64-linux ;;
    *) return 1 ;;
  esac
}

# words VALUE: prints the words of VALUE, separated by any whitespace, one per
# line.
words() {
  local -a list
  read -r -d '' -a list <<<"$1" || true
  ((${#list[@]})) && printf '%s\n' "${list[@]}"
  return 0
}

# user_conf: prints the path of the runner user's nix.conf.
user_conf() {
  echo "${XDG_CONFIG_HOME:-$HOME/.config}/nix/nix.conf"
}

# nix_bin: prints the path of the installed nix.
nix_bin() {
  echo "$ROOT/nix/var/nix/profiles/default/bin/nix"
}
