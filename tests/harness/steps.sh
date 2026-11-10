# shellcheck shell=bash disable=SC2154,SC2034 # shared with tests/harness
# The steps of action.yml, and runs of a script as its step runs it: through
# run-step.sh of the library, with the variables of its run line. Sourced by
# tests/run.sh.

STEP_SHELL='/usr/bin/bash --noprofile --norc -p -e -o pipefail {0}'
# The run line of a step; the step is the first group, its variables the
# second.
# shellcheck disable=SC2016 # the text of action.yml, not expanded here
STEP_RUN_RE='^/usr/bin/bash -p "\$SHELL_LIB/run-step\.sh" "\$GITHUB_ACTION_PATH/scripts/step" ([a-z-]+)(( [A-Z_]+)*)$'
# Separates the fields of action_steps; not whitespace, so that a field can be
# empty.
FIELD_SEPARATOR=$'\x1f'
# Variables of the stubs, which a step passes on to them.
STUB_VARS=(CALLS FIXTURES SUDO_FAILS)

# action_steps: prints the uses, the shell, the SHELL_LIB of env and the run of
# each step of action.yml, separated by FIELD_SEPARATOR, with a run folded
# over several lines joined.
action_steps() {
  awk -v sep="$FIELD_SEPARATOR" '
    function flush() { if (in_step) print uses sep shell sep lib sep run }
    /^    - / { flush(); in_step = 1; uses = shell = lib = run = key = ""; sub(/^    - /, "      ") }
    in_step && /^      [a-z-]+:/ {
      key = $1; value = $0; sub(/^      [a-z-]+: */, "", value)
      if (key == "uses:") uses = value
      if (key == "shell:") shell = value
      if (key == "run:" && value != ">-") run = value
      next
    }
    in_step && key == "env:" && /^        SHELL_LIB:/ {
      lib = $0; sub(/^        SHELL_LIB: */, "", lib)
    }
    in_step && key == "run:" && /^        / {
      line = $0; sub(/^ +/, "", line); run = run (run == "" ? "" : " ") line
    }
    END { flush() }
  ' "$root/action.yml"
}

# step_variables STEP: prints the variables that the run line of STEP in
# action.yml names, one per line; nothing if no step is STEP.
step_variables() {
  local step=$1 uses shell lib command names
  while IFS=$FIELD_SEPARATOR read -r uses shell lib command; do
    if [[ $command =~ $STEP_RUN_RE && ${BASH_REMATCH[1]} == "$step" ]]; then
      read -r -a names <<<"${BASH_REMATCH[2]}"
      printf '%s\n' "${names[@]}"
    fi
  done < <(action_steps)
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
