# shellcheck shell=bash disable=SC2154,SC2034 # shared with tests/harness
# Unit tests of scripts/step/unsupported-os.sh.

setup
run "unsupported-os: names the runner" fail step/unsupported-os.sh RUNNER_OS=Windows
expect message "::error::Unsupported runner Windows: use a GitHub-hosted Linux runner"
finish
