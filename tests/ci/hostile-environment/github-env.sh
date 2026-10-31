#!/usr/bin/env bash
# Sets, for the later steps of the hostile job, exported functions that replace
# commands of the scripts of the action, and shell options with a PS4 that runs
# code. Each records in $RUNNER_TEMP when a script of the action uses it.
set -euo pipefail

# Commands of the scripts, builtins too; each function runs the real command.
COMMANDS=(sha256sum tar cat mktemp id dirname printf echo)

# recorder MARKER WHAT: shell code that appends WHAT to $RUNNER_TEMP/MARKER when
# run by a script of the action.
recorder() {
  local marker=$1 what=$2
  # shellcheck disable=SC2016 # expanded by the scripts of the action
  printf 'case $0 in */scripts/*.sh) builtin printf "%%s %%s\\n" "$0" %s >>"$RUNNER_TEMP/%s" ;; esac' \
    "$what" "$marker"
}

for name in "${COMMANDS[@]}"; do
  printf 'BASH_FUNC_%s%%%%=() { %s; command %s "$@"; }\n' \
    "$name" "$(recorder functions-ran "$name")" "$name"
done >>"$GITHUB_ENV"
{
  echo "SHELLOPTS=xtrace"
  echo "PS4=\$($(recorder ps4-ran PS4))+ "
} >>"$GITHUB_ENV"
