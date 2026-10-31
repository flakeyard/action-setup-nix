#!/usr/bin/env bash
# Stores the GitHub token for Nix's fetchers in the runner user's nix.conf,
# readable only by that user. check.sh validated and masked it.
#
# Inputs (environment): TOKEN.
set -euo pipefail
lib=$(dirname -- "${BASH_SOURCE[0]}")/../lib
# shellcheck source-path=SCRIPTDIR source=../lib/env.sh
source "$lib/env.sh"
# shellcheck source-path=SCRIPTDIR source=../lib/runner.sh
source "$lib/runner.sh"

conf=$(user_conf)
mkdir -p -- "$(dirname -- "$conf")"
umask 077
# noclobber: check.sh found no such file, so one now is not ours.
set -o noclobber
printf 'access-tokens = github.com=%s\n' "$TOKEN" >"$conf"
