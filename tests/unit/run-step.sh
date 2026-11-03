# shellcheck shell=bash disable=SC2154,SC2034 # shared with tests/harness
# shellcheck disable=SC2016 # code for the scripts, not expanded here
# Unit tests of scripts/run-step.sh.

# Variables that earlier steps of a job can set to run code in the action.
hostile_vars=(
  'BASH_FUNC_printf%%=() { builtin echo INJECTED; }'
  'BASH_FUNC_cat%%=() { builtin echo INJECTED; }'
  SHELLOPTS=xtrace 'PS4=$(builtin echo PS4-RAN >&2)' BASHOPTS=extdebug
  BASH_ENV=/dev/null NIX_CONFIG="sandbox = false"
)

# step_setup: as-action.sh, which runs run-step.sh like the steps of
# action.yml.
step_setup() {
  setup
  printf '#!/usr/bin/bash -p\n%s\n' \
    '/usr/bin/bash -p "${BASH_SOURCE[0]%/*}/run-step.sh" "$@"' >"$action/scripts/as-action.sh"
  chmod +x "$action/scripts/as-action.sh"
}

# probe_setup: also the step probe, which prints what it got: its functions,
# its shell options, a child's functions and its environment.
probe_setup() {
  step_setup
  cat >"$action/scripts/step/probe.sh" <<'EOF2'
printf 'functions: %s\n' "$(declare -F | grep -c .)"
printf 'xtrace: %s\n' "$(set -o | grep -c 'xtrace.*on')"
printf 'child functions: %s\n' "$(bash -c 'declare -F | grep -c .')"
env
EOF2
}

probe_setup
run "run-step: no functions or options of the job" ok as-action.sh \
  "${hostile_vars[@]}" -- probe
expect message "functions: 0"
expect message "xtrace: 0"
expect message "child functions: 0"
expect no-message "INJECTED"
expect no-message "PS4-RAN"
expect no-message "BASH_FUNC_"
expect no-message "NIX_CONFIG"
finish

# The loader reads its variables when the first bash of a step starts, before
# run-step.sh: they reach that process, but not the scripts.
probe_setup
run "run-step: loader variables reach only the first process" ok as-action.sh \
  LD_PRELOAD=/nonexistent/preload.so LD_LIBRARY_PATH=/nonexistent -- probe
expect message "from LD_PRELOAD cannot be preloaded"
[[ -z $current ]] || ! grep -E '^LD_' "$work/stdout" ||
  report "the step got variables of the loader"
finish

probe_setup
run "run-step: the variables of the scripts" ok as-action.sh \
  SUBSTITUTERS=$'https://a\nhttps://b' KEYS=k TOKEN=t XDG_CONFIG_HOME=/x -- probe
for var in SUBSTITUTERS=https://a KEYS=k TOKEN=t RUNNER_OS=Linux RUNNER_ARCH=X64 \
  RUNNER_ENVIRONMENT=github-hosted RUNNER_TEMP="$work/temp" \
  GITHUB_OUTPUT="$work/output" GITHUB_PATH="$work/path" HOME="$work/home" \
  XDG_CONFIG_HOME=/x PATH="$root/tests/harness/stub:$sysbin"; do
  expect message "$var"
done
expect no-message "CALLS="
finish

step_setup
run "run-step: functions do not replace commands of step/check.sh" fail as-action.sh \
  "${hostile_vars[@]}" RUNNER_ARCH=X86 -- check
expect message "::error::Unsupported runner Linux/X86"
expect no-message "INJECTED"
finish

step_setup
run "run-step: only steps of the action" fail as-action.sh -- ../versions
expect message "invalid step name '../versions'"
finish

# action_steps: prints the shell and the run of each step of action.yml,
# separated by a tab, with a run folded over several lines joined.
action_steps() {
  awk '
    function flush() { if (in_step) print shell "\t" run }
    /^    - / { flush(); in_step = 1; shell = run = key = ""; sub(/^    - /, "      ") }
    in_step && /^      [a-z-]+:/ {
      key = $1; value = $0; sub(/^      [a-z-]+: */, "", value)
      if (key == "shell:") shell = value
      if (key == "run:") run = value
      next
    }
    in_step && key == "run:" && /^        / {
      line = $0; sub(/^ +/, "", line); run = run (run == "" ? "" : " ") line
    }
    END { flush() }
  ' "$root/action.yml"
}

STEP_SHELL='/usr/bin/bash --noprofile --norc -p -e -o pipefail {0}'
STEP_RUN_RE='^/usr/bin/bash -p "\$GITHUB_ACTION_PATH/scripts/run-step.sh" [a-z-]+$'
UNSUPPORTED_OS_RUN='bash "$GITHUB_ACTION_PATH/scripts/step/unsupported-os.sh"'

setup
current="run-step: every Linux step of action.yml uses it"
linux_steps=0
while IFS=$'\t' read -r shell command; do
  if [[ $shell == bash && $command == "$UNSUPPORTED_OS_RUN" ]]; then
    continue
  elif [[ $shell == "$STEP_SHELL" && $command =~ $STEP_RUN_RE ]]; then
    linux_steps=$((linux_steps + 1))
  else
    report "a step does not use run-step.sh: shell '$shell', run '$command'"
  fi
done < <(action_steps)
((linux_steps == 4)) || report "$linux_steps steps through run-step.sh, expected 4"
finish
