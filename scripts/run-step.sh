#!/usr/bin/env bash
# Usage: /usr/bin/bash -p scripts/run-step.sh STEP
#
# Runs step/STEP.sh, the script of one step of the action, with only the
# variables the scripts read. Earlier steps can set any variable for the rest
# of the job, such as exported functions (BASH_FUNC_name%%) that replace
# commands, SHELLOPTS and PS4 that run code, or LD_PRELOAD. bash -p imports no
# functions, SHELLOPTS or BASHOPTS and reads no BASH_ENV, here and in the step.
set -euo pipefail

# The inputs of the steps, the runner's variables and the user's. PATH is the
# job's, for step/check.sh; lib/env.sh replaces it.
ALLOWED_VARS=(
  SUBSTITUTERS KEYS TOKEN
  RUNNER_OS RUNNER_ARCH RUNNER_ENVIRONMENT RUNNER_TEMP
  GITHUB_OUTPUT GITHUB_PATH
  HOME XDG_CONFIG_HOME PATH
)

# A name only, so that no path leaves step/.
STEP_RE='^[a-z-]+$'

step=${1:?usage: run-step.sh STEP}
[[ $step =~ $STEP_RE ]] || {
  echo "::error::run-step.sh: invalid step name '$step'."
  exit 2
}

vars=()
for name in "${ALLOWED_VARS[@]}"; do
  if [[ -v $name ]]; then
    vars+=("$name=${!name}")
  fi
done
# Only absolute paths and builtins until then: PATH is the job's.
exec /usr/bin/env -i "${vars[@]}" /usr/bin/bash -p "${BASH_SOURCE[0]%/*}/step/$step.sh"
