# shellcheck shell=bash
# The environment of every step: the step_environment of the library, the
# root of the file system and the pinned release. Sourced first, not run.

# shellcheck source=/dev/null # the library, from SHELL_LIB
source "$SHELL_LIB/env.sh"
step_environment

# Root of the file system. Only the tests change it, in their own copy of the
# action; nothing at run time can.
# shellcheck disable=SC2034 # used by the steps and runner.sh
ROOT=

ACTION_DIR=$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd)
# shellcheck source-path=SCRIPTDIR source=../../versions.sh
source "$ACTION_DIR/versions.sh"
