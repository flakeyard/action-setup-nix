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

# run_with_job_path NAME STEP [VAR=VALUE...]: runs step/STEP.sh like
# action.yml does, with the fake tools first on PATH and the variables that
# earlier steps can set to run code, and checks that it ran none of them.
run_with_job_path() {
  local name=$1 step=$2
  fake_job_tools
  run_hostile "$name" ok "$action" "$step" "${@:3}" \
    PATH="$work/job-bin:$root/tests/harness/stub:$sysbin"
  [[ -z $current || ! -e $work/job-tools-ran ]] \
    || report "ran tools of the job PATH: $(paste -sd';' "$work/job-tools-ran")"
}
