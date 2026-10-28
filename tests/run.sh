#!/usr/bin/env bash
# Unit tests of the scripts of the action; see tests/lib.sh.
# Usage: tests/run.sh
set -uo pipefail

# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source-path=SCRIPTDIR source=unit/check.sh
source "$root/tests/unit/check.sh"
# shellcheck source-path=SCRIPTDIR source=unit/install.sh
source "$root/tests/unit/install.sh"
# shellcheck source-path=SCRIPTDIR source=unit/verify.sh
source "$root/tests/unit/verify.sh"
# shellcheck source-path=SCRIPTDIR source=unit/check-tarball.sh
source "$root/tests/unit/check-tarball.sh"
# shellcheck source-path=SCRIPTDIR source=unit/update-nix.sh
source "$root/tests/unit/update-nix.sh"
# shellcheck source-path=SCRIPTDIR source=unit/ci-scripts.sh
source "$root/tests/unit/ci-scripts.sh"

echo "passed: $passed, failed: $failed"
((failed == 0))
