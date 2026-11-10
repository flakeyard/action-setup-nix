# shellcheck shell=bash disable=SC2154,SC2034 # shared with tests/harness
# The steps of action.yml, which tests/run.sh reads into ACTION_JSON, and runs
# of a script as its step runs it: through run-step.sh of the library, with
# the variables of its run line, which STEP_RUN_FORM of the library reads.
# Sourced by tests/run.sh.

# Variables of the stubs, which a step passes on to them.
STUB_VARS=(CALLS FIXTURES SUDO_FAILS)

# step_variables STEP: prints the variables that the run line of STEP in
# action.yml names, one per line; nothing if no step is STEP.
step_variables() {
  local step=$1 command names
  while IFS= read -r command; do
    if [[ $command =~ $STEP_RUN_FORM && ${BASH_REMATCH[1]} == "$step" ]]; then
      read -r -a names <<<"${BASH_REMATCH[2]}"
      printf '%s\n' "${names[@]}"
    fi
  done < <(jq -r '.runs.steps[].run // empty' <<<"$ACTION_JSON")
}

# as_action: $action/scripts/as-action.sh, which runs run-step.sh of the
# library through /usr/bin/bash -p, like the steps of action.yml.
as_action() {
  # shellcheck disable=SC2016 # code for the script, not expanded here
  printf '#!/usr/bin/bash -p\n%s\n' \
    'exec /usr/bin/bash -p "$SHELL_LIB/run-step.sh" "${BASH_SOURCE[0]%/*}/step" "$@"' \
    >"$action/scripts/as-action.sh"
  chmod +x "$action/scripts/as-action.sh"
}

# run_step NAME EXPECTED STEP [VAR=VALUE...]: run step/STEP.sh like action.yml
# does, with only the variables of its run line and of the stubs.
run_step() {
  local name=$1 expected=$2 step=$3 variables=()
  mapfile -t variables < <(step_variables "$step")
  as_action
  run "$name" "$expected" as-action.sh "${@:4}" -- "$step" "${variables[@]}" "${STUB_VARS[@]}"
}
