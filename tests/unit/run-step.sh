# shellcheck shell=bash disable=SC2154,SC2034 # shared with tests/lib.sh
# shellcheck disable=SC2016 # code for the scripts, not expanded here
# Unit tests of scripts/run-step.sh.

# Variables that earlier steps of a job can set to run code in the action.
hostile_vars=(
  'BASH_FUNC_printf%%=() { builtin echo INJECTED; }'
  'BASH_FUNC_cat%%=() { builtin echo INJECTED; }'
  SHELLOPTS=xtrace 'PS4=$(builtin echo PS4-RAN >&2)' BASHOPTS=extdebug
  BASH_ENV=/dev/null NIX_CONFIG="sandbox = false" LD_PRELOAD=
)

# step_setup: step.sh, which runs run-step.sh like the steps of action.yml.
step_setup() {
  setup
  printf '#!/usr/bin/bash -p\n%s\n' \
    '/usr/bin/bash -p "${BASH_SOURCE[0]%/*}/run-step.sh" "$@"' >"$action/scripts/step.sh"
  chmod +x "$action/scripts/step.sh"
}

# probe_setup: also probe.sh, a script of the action that prints what it got:
# its functions, its shell options, a child's functions and its environment.
probe_setup() {
  step_setup
  cat >"$action/scripts/probe.sh" <<'EOF2'
printf 'functions: %s\n' "$(declare -F | grep -c .)"
printf 'xtrace: %s\n' "$(set -o | grep -c 'xtrace.*on')"
printf 'child functions: %s\n' "$(bash -c 'declare -F | grep -c .')"
env
EOF2
}

# --- run-step.sh ------------------------------------------------------------

probe_setup
run "run-step: no functions or options of the job" ok step.sh \
  "${hostile_vars[@]}" -- probe.sh
expect message "functions: 0"
expect message "xtrace: 0"
expect message "child functions: 0"
expect no-message "INJECTED"
expect no-message "PS4-RAN"
expect no-message "BASH_FUNC_"
expect no-message "NIX_CONFIG"
expect no-message "LD_PRELOAD"
finish

probe_setup
run "run-step: the variables of the scripts" ok step.sh \
  SUBSTITUTERS=$'https://a\nhttps://b' KEYS=k TOKEN=t XDG_CONFIG_HOME=/x -- probe.sh
for var in SUBSTITUTERS=https://a KEYS=k TOKEN=t RUNNER_OS=Linux RUNNER_ARCH=X64 \
  RUNNER_ENVIRONMENT=github-hosted RUNNER_TEMP="$work/temp" \
  GITHUB_OUTPUT="$work/output" GITHUB_PATH="$work/path" HOME="$work/home" \
  XDG_CONFIG_HOME=/x PATH="$root/tests/bin:$sysbin"; do
  expect message "$var"
done
expect no-message "CALLS="
finish

step_setup
run "run-step: functions do not replace commands of check.sh" fail step.sh \
  "${hostile_vars[@]}" RUNNER_ARCH=X86 -- check.sh
expect message "::error::Unsupported runner Linux/X86"
expect no-message "INJECTED"
finish

step_setup
run "run-step: only scripts of the action" fail step.sh -- ../versions.sh
expect message "invalid script name '../versions.sh'"
finish

setup
step_lines=$(grep -cxF -- '      shell: /usr/bin/bash --noprofile --norc -p -e -o pipefail {0}' "$root/action.yml")
run_lines=$(grep -cE '^      run: /usr/bin/bash -p "\$GITHUB_ACTION_PATH/scripts/run-step.sh" [a-z-]+\.sh$' "$root/action.yml")
current="run-step: every Linux step of action.yml uses it"
[[ $step_lines == 4 && $run_lines == 4 ]] ||
  report "$step_lines steps with bash -p, $run_lines through run-step.sh, expected 4"
finish
