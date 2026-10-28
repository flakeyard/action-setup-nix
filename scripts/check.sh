#!/usr/bin/env bash
# Checks the runner and the inputs before anything is changed, and reports
# every problem at once.
#
# Inputs (environment): SUBSTITUTERS, KEYS, TOKEN.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

failed=false
error() {
  printf '::error::%s\n' "$1"
  failed=true
}

# The runner.
if [[ ${RUNNER_OS-} != Linux ]] || ! nix_system >/dev/null; then
  error "Unsupported runner ${RUNNER_OS-?}/${RUNNER_ARCH-?}: use a GitHub-hosted Linux runner on X64 or ARM64, such as ubuntu-24.04 or ubuntu-24.04-arm."
fi
if [[ ${RUNNER_ENVIRONMENT-} != github-hosted ]]; then
  error "Only GitHub-hosted runners are supported, not '${RUNNER_ENVIRONMENT-}'."
fi
if [[ -e $ROOT/.dockerenv || ! -d $ROOT/run/systemd/system ]]; then
  error "The Nix daemon needs systemd: run the job directly on the runner, not in a container."
fi
if ! sudo -n true 2>/dev/null; then
  error "The installation needs passwordless sudo."
fi
if [[ -r $ROOT/etc/os-release ]]; then
  # shellcheck disable=SC1091 # the runner's file
  os=$(. "$ROOT/etc/os-release" && echo "${ID-}/${VERSION_ID-}")
  tested=false
  for version in "${TESTED_UBUNTU[@]}"; do
    [[ $os == "ubuntu/$version" ]] && tested=true
  done
  $tested || printf '::warning::This action is not tested on %s; tested: Ubuntu %s.\n' \
    "$os" "${TESTED_UBUNTU[*]}"
fi

# Nix installed before.
found=()
[[ -e $ROOT/nix ]] && found+=("/nix")
[[ -e $ROOT/etc/nix ]] && found+=("/etc/nix")
[[ -r $ROOT/etc/group ]] && grep -q '^nixbld:' "$ROOT/etc/group" && found+=("group nixbld")
command -v nix >/dev/null && found+=("nix on PATH")
[[ -e $(user_conf) ]] && found+=("$(user_conf)")
if ((${#found[@]})); then
  error "Nix was installed on this runner before (found: ${found[*]}); this action installs Nix only on a clean runner, once per job."
fi

# Inputs. Values go into nix.conf, which the daemon reads: no whitespace inside
# a value, no query (?trusted=1 disables signature checks), no fragment (#
# starts a comment) and no user information.
substituters=() keys=()
mapfile -t substituters < <(words "${SUBSTITUTERS-}")
mapfile -t keys < <(words "${KEYS-}")
for url in "${substituters[@]}"; do
  if ! [[ $url =~ ^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[A-Za-z0-9._~/-]*)?$ ]]; then
    error "Invalid extra substituter '$url': expected an https URL without user information, query or fragment."
  fi
done
for key in "${keys[@]}"; do
  if ! [[ $key =~ ^[A-Za-z0-9._-]+:[A-Za-z0-9+/]{43}=$ ]]; then
    error "Invalid extra trusted public key '$key': expected <name>:<base64 Ed25519 key>."
  fi
done
if ((${#keys[@]} && ! ${#substituters[@]})); then
  error "extra-trusted-public-keys is set without extra-substituters."
fi
if ((${#substituters[@]} && ! ${#keys[@]})); then
  echo "::notice::Extra substituters without extra keys: their paths must be signed by cache.nixos.org."
fi

if [[ -n ${TOKEN-} ]]; then
  if [[ $TOKEN =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "::add-mask::$TOKEN"
  else
    # The value is not printed: it may be a secret.
    error "Invalid github-token: expected only letters, digits, underscores, dots and hyphens."
  fi
fi

if $failed; then
  exit 1
fi
