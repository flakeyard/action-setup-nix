# shellcheck shell=bash disable=SC2154,SC2034 # shared with tests/harness
# A job PATH whose tools are fakes. The steps get the job's PATH and must use
# only builtins until lib/env.sh replaces it. Sourced by tests/run.sh.

# Tools of the scripts and of the runner that earlier steps can replace.
JOB_TOOLS=(bash env dirname id mktemp cat cp mkdir rm sed grep curl sha256sum tar xz sudo)

# fake_job_tools: $work/job-bin with a fake of each of JOB_TOOLS, which records
# its call in $work/job-tools-ran and on stderr, and fails.
fake_job_tools() {
  local bin=$work/job-bin name
  mkdir -p "$bin"
  for name in "${JOB_TOOLS[@]}"; do
    # shellcheck disable=SC2016 # expanded by the fake
    printf '#!/bin/sh\necho "%s $*" >>"%s"\necho "fake %s of the job PATH" >&2\nexit 1\n' \
      "$name" "$work/job-tools-ran" "$name" >"$bin/$name"
    chmod +x "$bin/$name"
  done
}

# as_step: $action/scripts/as-step.sh, which runs step/STEP.sh like run-step.sh,
# through /usr/bin/bash -p, but with every variable of the test.
as_step() {
  # shellcheck disable=SC2016 # code for the script, not expanded here
  printf '#!/usr/bin/bash -p\n%s\n' \
    'exec /usr/bin/bash -p "${BASH_SOURCE[0]%/*}/step/$1.sh"' >"$action/scripts/as-step.sh"
  chmod +x "$action/scripts/as-step.sh"
}

# run_with_job_path NAME STEP [VAR=VALUE...]: runs step/STEP.sh with the fake
# tools first on PATH, and checks that it ran none of them.
run_with_job_path() {
  local name=$1 step=$2
  fake_job_tools
  as_step
  run "$name" ok as-step.sh "${@:3}" \
    PATH="$work/job-bin:$root/tests/harness/stub:$sysbin" -- "$step"
  [[ -z $current || ! -e $work/job-tools-ran ]] ||
    report "ran tools of the job PATH: $(paste -sd';' "$work/job-tools-ran")"
}
