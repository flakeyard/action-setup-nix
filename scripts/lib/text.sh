# shellcheck shell=bash
# Inputs as words, and values safe to print. Sourced after env.sh, not run.

# words VALUE: prints the words of VALUE, separated by any whitespace, one per
# line.
words() {
  local -a list
  IFS=$' \t\n\r\v\f' read -r -d '' -a list <<<"$1" || true
  ((${#list[@]})) && printf '%s\n' "${list[@]}"
  return 0
}

# shown VALUE: VALUE with control characters replaced, safe to print in a
# workflow command.
shown() {
  printf '%s' "${1//[[:cntrl:]]/?}"
}
