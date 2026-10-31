#!/usr/bin/env bash
# Unit tests of the scripts of the action; see tests/harness/.
# Usage: tests/run.sh
set -uo pipefail

# shellcheck source-path=SCRIPTDIR source=harness/env.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/harness/env.sh"
# shellcheck source-path=SCRIPTDIR source=harness/action.sh
source "$root/tests/harness/action.sh"
# shellcheck source-path=SCRIPTDIR source=harness/tarball.sh
source "$root/tests/harness/tarball.sh"
# shellcheck source-path=SCRIPTDIR source=harness/case.sh
source "$root/tests/harness/case.sh"

# shellcheck source-path=SCRIPTDIR source=unit/step/check.sh
source "$root/tests/unit/step/check.sh"
# shellcheck source-path=SCRIPTDIR source=unit/step/unsupported-os.sh
source "$root/tests/unit/step/unsupported-os.sh"
# shellcheck source-path=SCRIPTDIR source=unit/lib/nix-conf.sh
source "$root/tests/unit/lib/nix-conf.sh"
# shellcheck source-path=SCRIPTDIR source=unit/step/install.sh
source "$root/tests/unit/step/install.sh"
# shellcheck source-path=SCRIPTDIR source=unit/step/configure-token.sh
source "$root/tests/unit/step/configure-token.sh"
# shellcheck source-path=SCRIPTDIR source=unit/step/verify.sh
source "$root/tests/unit/step/verify.sh"
# shellcheck source-path=SCRIPTDIR source=unit/update/check-tarball.sh
source "$root/tests/unit/update/check-tarball.sh"
# shellcheck source-path=SCRIPTDIR source=unit/update/nix.sh
source "$root/tests/unit/update/nix.sh"
# shellcheck source-path=SCRIPTDIR source=unit/run-step.sh
source "$root/tests/unit/run-step.sh"
# shellcheck source-path=SCRIPTDIR source=unit/github/required.sh
source "$root/tests/unit/github/required.sh"
# shellcheck source-path=SCRIPTDIR source=unit/github/commit-status.sh
source "$root/tests/unit/github/commit-status.sh"

echo "passed: $passed, failed: $failed"
((failed == 0))
