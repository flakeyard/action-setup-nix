# shellcheck shell=bash
# Inputs as words, and values safe to print. Sourced after env.sh, not run.

# words ARRAY VALUE: sets the array named ARRAY to the words of VALUE,
# separated by any whitespace. read fails at the end of its input, which has
# no NUL to stop at, so its status is ignored.
words() {
  local -n words_list=$1
  # shellcheck disable=SC2034 # words_list names the caller's array.
  IFS=$' \t\n\r\v\f' read -r -d '' -a words_list <<<"$2" || true
}

# shown VALUE: VALUE with control characters replaced, safe to print in a
# workflow command.
shown() {
  printf '%s' "${1//[[:cntrl:]]/?}"
}
