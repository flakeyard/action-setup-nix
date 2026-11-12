#!/usr/bin/env bash
# Unit tests of the scripts of the action; see tests/harness/. They read
# action.yml with mikefarah yq v4, which GitHub-hosted runners have; elsewhere
# run them with: nix shell nixpkgs#yq-go -c tests/run.sh
# Usage: tests/run.sh
set -uo pipefail

# shellcheck source-path=SCRIPTDIR source=harness/env.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/harness/env.sh"
# shellcheck source-path=SCRIPTDIR source=harness/shell-lib.sh
source "$root/tests/harness/shell-lib.sh"
# The harness of the library; not its public API, used only by tests.
# shellcheck source=/dev/null
source "$SHELL_LIB/internal/testing/case.sh"
# shellcheck source=/dev/null
source "$SHELL_LIB/internal/testing/checks.sh"
# shellcheck source=/dev/null
source "$SHELL_LIB/internal/testing/yaml.sh"
# shellcheck source=/dev/null
source "$SHELL_LIB/internal/testing/consumer/library.sh"
# shellcheck source=/dev/null
source "$SHELL_LIB/internal/testing/consumer/action.sh"
# shellcheck source=/dev/null
source "$SHELL_LIB/internal/testing/consumer/step.sh"
# The variables of the stubs of tests/harness/stub, which a step passes on to
# them.
# shellcheck disable=SC2034 # read by internal/testing/consumer/step.sh
stub_variables=(SUDO_FAILS)
# The steps get a copy of the library whose SYSTEM_PATH is the tools of the
# tests.
shell_lib=$shared/shell-lib
copy_library "$shell_lib" "$root/tests/harness/stub:$sysbin"
# shellcheck source-path=SCRIPTDIR source=harness/checks.sh
source "$root/tests/harness/checks.sh"
# shellcheck source-path=SCRIPTDIR source=harness/action.sh
source "$root/tests/harness/action.sh"
# shellcheck source-path=SCRIPTDIR source=harness/tarball.sh
source "$root/tests/harness/tarball.sh"
# The steps of every test come from action.yml, read with yq.
# shellcheck disable=SC2034 # read by internal/testing/yaml.sh
code_root=$root
require_yq action.yml || {
  conclude
  exit 1
}
# shellcheck source-path=SCRIPTDIR source=harness/job-path.sh
source "$root/tests/harness/job-path.sh"

# shellcheck source-path=SCRIPTDIR source=unit/step/check.sh
source "$root/tests/unit/step/check.sh"
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
# shellcheck source-path=SCRIPTDIR source=unit/action.sh
source "$root/tests/unit/action.sh"

conclude
