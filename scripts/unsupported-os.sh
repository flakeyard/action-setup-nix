#!/usr/bin/env bash
# Fails with a clear message on runners other than Linux, where the steps of
# the action cannot even start: they use /usr/bin/bash.
#
# Inputs (environment): RUNNER_OS.
echo "::error::Unsupported runner ${RUNNER_OS-?}: use a GitHub-hosted Linux runner on X64 or ARM64, such as ubuntu-24.04 or ubuntu-24.04-arm."
exit 1
