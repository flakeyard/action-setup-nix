#!/usr/bin/env bash
# Fails with a clear message on runners other than Linux, where the steps of
# the action cannot even start: they use /usr/bin/bash.
#
# Inputs (environment): RUNNER_OS.
# lib/runner.sh only defines functions, which also the bash of macOS and of
# Windows runners reads.
# shellcheck source-path=SCRIPTDIR source=../lib/runner.sh
source "${BASH_SOURCE[0]%/*}/../lib/runner.sh"
printf '::error::%s\n' "$(unsupported_runner "${RUNNER_OS-?}")"
exit 1
