# shellcheck shell=bash disable=SC2154,SC2034 # shared with tests/harness
# shellcheck disable=SC2016 # code for the scripts, not expanded here
# Unit tests of the steps of action.yml. run-step.sh has its own tests in the
# library.

# Variables that earlier steps of a job can set to run code in the action.
hostile_vars=(
  'BASH_FUNC_printf%%=() { builtin echo INJECTED; }'
  'BASH_FUNC_sudo%%=() { builtin echo INJECTED; }'
  SHELLOPTS=xtrace 'PS4=$(builtin echo PS4-RAN >&2)' BASHOPTS=extdebug
  BASH_ENV=/dev/null NIX_CONFIG="sandbox = false"
)

# The library step at a pinned commit, and its directory.
LIBRARY_USES_FORM='^flakeyard/action-shell-lib@[0-9a-f]{40}$'
LIBRARY_PATH='${{ steps.lib.outputs.path }}'

setup_action
run_step "action: functions do not replace commands of step/check.sh" fail check \
  "${hostile_vars[@]}" SUDO_FAILS=1
expect message "::error::The installation needs passwordless sudo."
expect no-message "INJECTED"
expect no-message "PS4-RAN"
finish

yaml_check "$ACTION_JSON" "action: the library is the first step" \
  '.runs.steps[0] | .id == "lib" and (.uses | test($form))' --arg form "$LIBRARY_USES_FORM"
yaml_check "$ACTION_JSON" "action: every other step runs through run-step.sh" \
  '.runs.steps[1:] | length == 4 and all(.shell == $shell
    and .env.SHELL_LIB == $lib and (.run | test($run)))' \
  --arg shell "$STEP_SHELL" --arg lib "$LIBRARY_PATH" --arg run "$STEP_RUN_RE"

workflow=$(code_root=$root load_yaml .github/workflows/test.yaml)
yaml_check "$workflow" "action: every use of the library names the commit of action.yml" \
  '[.. | objects | .uses? // empty | select(startswith("flakeyard/action-shell-lib@"))]
  | length > 0 and all(. == $uses)' \
  --arg uses "$(jq -r '.runs.steps[0].uses' <<<"$ACTION_JSON")"
