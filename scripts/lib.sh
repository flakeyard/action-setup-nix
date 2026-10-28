# shellcheck shell=bash
# Shared by the scripts of the action; sourced, not run.

# Root of the file system and the tools of the runner. Only the tests change
# them, in their own copy of the action; nothing at run time can.
ROOT=
SYSTEM_PATH=/usr/sbin:/usr/bin:/sbin:/bin

# PATH of the job, which earlier steps can change, and the runner's own.
# shellcheck disable=SC2034 # used by check.sh
JOB_PATH=${PATH-}
export PATH=$SYSTEM_PATH LC_ALL=C

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
  IFS=$' \t\n\r\v\f' read -r -d '' -a list <<<"$1" || true
  ((${#list[@]})) && printf '%s\n' "${list[@]}"
  return 0
}

# shown VALUE: VALUE with control characters replaced, safe to print in a
# workflow command.
shown() {
  printf '%s' "${1//[[:cntrl:]]/?}"
}

# user_conf: prints the path of the runner user's nix.conf.
user_conf() {
  echo "${XDG_CONFIG_HOME:-$HOME/.config}/nix/nix.conf"
}

# nix_bin: prints the path of the installed nix.
nix_bin() {
  echo "$ROOT/nix/var/nix/profiles/default/bin/nix"
}
