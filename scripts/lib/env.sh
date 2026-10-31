# shellcheck shell=bash
# The environment of every step: strict mode, the paths of the runner and the
# pinned release. Sourced first, not run.

# set -e also in command substitutions.
shopt -s inherit_errexit

# Root of the file system and the tools of the runner. Only the tests change
# them, in their own copy of the action; nothing at run time can.
# shellcheck disable=SC2034 # used by the steps and runner.sh
ROOT=
SYSTEM_PATH=/usr/sbin:/usr/bin:/sbin:/bin

# PATH of the job, which earlier steps can change, and the runner's own.
# shellcheck disable=SC2034 # used by step/check.sh
JOB_PATH=${PATH-}
export PATH=$SYSTEM_PATH LC_ALL=C

ACTION_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source-path=SCRIPTDIR source=../../versions.sh
source "$ACTION_DIR/versions.sh"
