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

setup_action
run_step "action: functions do not replace commands of step/check.sh" fail check \
  "${hostile_vars[@]}" SUDO_FAILS=1
expect message "::error::The installation needs passwordless sudo."
expect no-message "INJECTED"
expect no-message "PS4-RAN"
finish

check_action_steps "$ACTION_JSON"
yaml_check "$ACTION_JSON" "action: the library and the four steps of the action" \
  '.runs.steps | length == 5'
code_root=$root check_library_pins
