# shellcheck shell=bash disable=SC2154,SC2034 # shared with tests/harness
# shellcheck disable=SC2016 # code for the scripts, not expanded here
# Unit tests of the steps of action.yml. run-step.sh has its own tests in the
# library.

# Variables that earlier steps of a job can set to change the action, besides
# those that run_hostile of the library sets.
hostile_vars=(
  'BASH_FUNC_sudo%%=() { builtin echo INJECTED; }'
  NIX_CONFIG="sandbox = false"
)

setup_action
run_hostile "action: the environment does not reach step/check.sh" fail "$action" check \
  "${hostile_vars[@]}" SUDO_FAILS=1
expect message "::error::The installation needs passwordless sudo."
expect no-message "INJECTED"
finish

code_root=$root check_action_steps action.yml
yaml_check "$(code_root=$root load_yaml action.yml)" "action: the library and the four steps of the action" \
  '.runs.steps | length == 5'
code_root=$root check_library_pins
