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

# The library step: the pinned commit, then the release as a comment.
LIBRARY_STEP_RE='^flakeyard/action-shell-lib@[0-9a-f]{40} # v[0-9.]+$'
LIBRARY_PATH='${{ steps.lib.outputs.path }}'

setup_action
run_step "action: functions do not replace commands of step/check.sh" fail check \
  "${hostile_vars[@]}" SUDO_FAILS=1
expect message "::error::The installation needs passwordless sudo."
expect no-message "INJECTED"
expect no-message "PS4-RAN"
finish

setup
current="action: the library first, then every step through its run-step.sh"
steps=0
while IFS=$FIELD_SEPARATOR read -r uses shell lib command; do
  steps=$((steps + 1))
  if ((steps == 1)); then
    [[ $uses =~ $LIBRARY_STEP_RE ]] || report "the first step is not the library: '$uses'"
  elif [[ $shell != "$STEP_SHELL" || $lib != "$LIBRARY_PATH" || ! $command =~ $STEP_RUN_RE ]]; then
    report "a step does not use run-step.sh: shell '$shell', SHELL_LIB '$lib', run '$command'"
  fi
done < <(action_steps)
((steps == 5)) || report "$steps steps, expected the library and 4 more"
finish

setup
current="action: every use of the library names the commit of action.yml"
pinned=$(pinned_library_commit)
while IFS= read -r use; do
  [[ $use == *"@$pinned "* ]] || report "another commit: $use"
done < <(grep -rhoE 'flakeyard/action-shell-lib@[^ ]+ ' "$root/action.yml" "$root/.github")
finish
