#!/usr/bin/env bash
# Checks the runner and the inputs before anything is changed, and reports
# every problem at once.
#
# Inputs (environment): SUBSTITUTERS, KEYS, TOKEN.
set -euo pipefail
lib=$(dirname -- "${BASH_SOURCE[0]}")/../lib
# shellcheck source-path=SCRIPTDIR source=../lib/env.sh
source "$lib/env.sh"
# shellcheck source-path=SCRIPTDIR source=../lib/runner.sh
source "$lib/runner.sh"
# shellcheck source-path=SCRIPTDIR source=../lib/text.sh
source "$lib/text.sh"

# Values go into nix.conf, which the daemon reads: no whitespace inside a
# value, no query (?trusted=1 disables signature checks), no fragment (#
# starts a comment) and no user information.
SUBSTITUTER_RE='^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[A-Za-z0-9._~/-]*)?$'
# <name>:<base64 of a 32-byte Ed25519 key>.
PUBLIC_KEY_RE='^[A-Za-z0-9._-]+:[A-Za-z0-9+/]{43}=$'
TOKEN_RE='^[A-Za-z0-9_.-]+$'

failed=false
error() {
  printf '::error::%s\n' "$1"
  failed=true
}

# The runner.

# is_supported_runner: a Linux runner on X64 or ARM64.
is_supported_runner() {
  [[ ${RUNNER_OS-} == Linux ]] && nix_system >/dev/null
}

# runs_on_host_with_systemd: the job runs on the runner, not in a container,
# and systemd runs there.
runs_on_host_with_systemd() {
  [[ ! -e $ROOT/.dockerenv && -d $ROOT/run/systemd/system ]]
}

check_runner() {
  is_supported_runner ||
    error "Unsupported runner ${RUNNER_OS-?}/${RUNNER_ARCH-?}: use a GitHub-hosted Linux runner on X64 or ARM64, such as ubuntu-24.04 or ubuntu-24.04-arm."
  [[ ${RUNNER_ENVIRONMENT-} == github-hosted ]] ||
    error "Only GitHub-hosted runners are supported, not '${RUNNER_ENVIRONMENT-}'."
  runs_on_host_with_systemd ||
    error "The Nix daemon needs systemd: run the job directly on the runner, not in a container."
  sudo -n true 2>/dev/null ||
    error "The installation needs passwordless sudo."
}

# is_tested_ubuntu OS: OS, as ID/VERSION_ID, is an Ubuntu release that the CI
# of this action runs on.
is_tested_ubuntu() {
  local os=$1 version
  for version in "${TESTED_UBUNTU[@]}"; do
    [[ $os == "ubuntu/$version" ]] && return 0
  done
  return 1
}

warn_if_untested_os() {
  local os
  [[ -r $ROOT/etc/os-release ]] || return 0
  # shellcheck disable=SC1091 # the runner's file
  os=$(. "$ROOT/etc/os-release" && echo "${ID-}/${VERSION_ID-}")
  is_tested_ubuntu "$os" ||
    printf '::warning::This action is not tested on %s; tested: Ubuntu %s.\n' \
      "$os" "${TESTED_UBUNTU[*]}"
}

# Nix installed before.

# previous_nix_traces: prints what an earlier installation of Nix left on the
# runner, one per line.
previous_nix_traces() {
  local path
  for path in "$ROOT"/{nix,etc/nix,etc/xdg/nix} \
    "$ROOT"/etc/systemd/system/nix-daemon.* "$ROOT"/etc/*.backup-before-nix; do
    if [[ -e $path ]]; then
      printf '%s\n' "${path#"$ROOT"}"
    fi
  done
  if [[ -r $ROOT/etc/group ]] && grep -q '^nixbld:' "$ROOT/etc/group"; then
    echo "group nixbld"
  fi
  if PATH=$JOB_PATH command -v nix >/dev/null; then
    echo "nix on PATH"
  fi
  if [[ -e $(user_conf) ]]; then
    user_conf
  fi
}

check_clean_runner() {
  local found=()
  mapfile -t found < <(previous_nix_traces)
  if ((${#found[@]})); then
    error "Nix was installed on this runner before (found: ${found[*]}); this action installs Nix only on a clean runner, once per job."
  fi
}

# Inputs.

# check_substituters URL...
check_substituters() {
  local url
  for url in "$@"; do
    [[ $url =~ $SUBSTITUTER_RE ]] ||
      error "Invalid extra substituter '$(shown "$url")': expected an https URL without user information, query or fragment."
  done
}

# check_keys KEY...
check_keys() {
  local key
  for key in "$@"; do
    [[ $key =~ $PUBLIC_KEY_RE ]] ||
      error "Invalid extra trusted public key '$(shown "$key")': expected <name>:<base64 Ed25519 key>."
  done
}

# check_cache_pairing SUBSTITUTER_COUNT KEY_COUNT
check_cache_pairing() {
  local substituters=$1 keys=$2
  if ((keys && ! substituters)); then
    error "extra-trusted-public-keys is set without extra-substituters."
  fi
  if ((substituters && ! keys)); then
    echo "::notice::Extra substituters without extra keys: their paths must be signed by cache.nixos.org."
  fi
}

check_token() {
  [[ -n ${TOKEN-} ]] || return 0
  if [[ $TOKEN =~ $TOKEN_RE ]]; then
    echo "::add-mask::$TOKEN"
  else
    # The value is not printed: it may be a secret.
    error "Invalid github-token: expected only letters, digits, underscores, dots and hyphens."
  fi
}

main() {
  local substituters=() keys=()
  mapfile -t substituters < <(words "${SUBSTITUTERS-}")
  mapfile -t keys < <(words "${KEYS-}")
  check_runner
  warn_if_untested_os
  check_clean_runner
  check_substituters "${substituters[@]}"
  check_keys "${keys[@]}"
  check_cache_pairing "${#substituters[@]}" "${#keys[@]}"
  check_token
  if $failed; then
    exit 1
  fi
}

main "$@"
