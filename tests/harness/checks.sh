# shellcheck shell=bash disable=SC2154 # shared with tests/harness
# Checks of the results of a step that internal/testing/checks.sh does not
# have. Sourced by tests/run.sh.

# expect_path ENTRY: the last run added ENTRY to GITHUB_PATH.
expect_path() {
  [[ -n $current ]] || return 0
  grep -qxF -- "$1" "$work/path" || report "no PATH entry '$1' in: $(cat -- "$work/path")"
}

# expect_file FILE CONTENT: FILE holds CONTENT.
expect_file() {
  [[ -n $current ]] || return 0
  [[ $(<"$1") == "$2" ]] || report "$1 is '$(<"$1")', expected '$2'"
}

# expect_mode FILE MODE: FILE has the octal mode MODE.
expect_mode() {
  [[ -n $current ]] || return 0
  [[ $(stat -c %a "$1") == "$2" ]] || report "$1 has mode $(stat -c %a "$1"), expected $2"
}
