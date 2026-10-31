# shellcheck shell=bash disable=SC2154,SC2034 # shared with tests/harness
# Runs a script of the action as a test case and checks its results. Sourced
# by tests/run.sh.

# run NAME EXPECTED SCRIPT [VAR=VALUE...] [-- ARG...]: run a script of the
# action in the test environment; EXPECTED is ok or fail.
run() {
  local name=$1 expected=$2 script=$3 status=0 vars=() args=()
  shift 3
  while (($#)) && [[ $1 != -- ]]; do
    vars+=("$1")
    shift
  done
  (($#)) && shift && args=("$@")
  env -i "${env_vars[@]}" "${vars[@]}" "$action/scripts/$script" "${args[@]}" \
    >"$work/stdout" 2>"$work/stderr" || status=$?
  current=$name
  if [[ $expected == fail && $status -eq 0 ]] || [[ $expected == ok && $status -ne 0 ]]; then
    report "expected $expected, exit status $status: $(cat "$work/stdout" "$work/stderr")"
  fi
}

report() {
  [[ -n $current ]] || return 0
  echo "FAIL $current: $1"
  failed=$((failed + 1))
  current=""
}

# expect KIND [VALUE...]: check the last run.
expect() {
  [[ -n $current ]] || return 0
  case $1 in
    message) grep -qF -- "$2" "$work/stdout" "$work/stderr" || report "no message '$2' in: $(cat "$work/stdout" "$work/stderr")" ;;
    no-message) ! grep -qF -- "$2" "$work/stdout" "$work/stderr" || report "unexpected message '$2'" ;;
    errors)
      local count
      count=$(grep -c '^::error::' "$work/stdout")
      [[ $count == "$2" ]] || report "$count errors, expected $2: $(cat "$work/stdout")"
      ;;
    call) grep -qF -- "$2" "$work/calls" || report "no call '$2' in: $(paste -sd';' "$work/calls")" ;;
    no-call) ! grep -qF -- "$2" "$work/calls" || report "unexpected call '$2'" ;;
    output) grep -qxF -- "$2" "$work/output" || report "no output '$2' in: $(cat "$work/output")" ;;
    path) grep -qxF -- "$2" "$work/path" || report "no PATH entry '$2' in: $(cat "$work/path")" ;;
    file)
      [[ $(<"$2") == "$3" ]] || report "$2 is '$(<"$2")', expected '$3'"
      ;;
    mode)
      [[ $(stat -c %a "$2") == "$3" ]] || report "$2 has mode $(stat -c %a "$2"), expected $3"
      ;;
  esac
}

finish() {
  if [[ -n $current ]]; then
    passed=$((passed + 1))
  fi
  current=""
  rm -rf -- "$work"
}
