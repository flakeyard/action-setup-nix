# shellcheck shell=bash disable=SC2034 # variables for the unit tests
# The environment of the unit tests, sourced first by tests/run.sh: the
# results so far, files shared by all tests and the tools of the scripts.
export LC_ALL=C

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
failed=0 passed=0 current=""
key=cache.example.org-1:$(printf 'k%.0s' {1..43})=

# shellcheck source-path=SCRIPTDIR source=../../versions.sh
source "$root/versions.sh"

# Files shared by all tests, removed at the end.
shared=$(mktemp -d)
trap 'rm -rf -- "$shared"' EXIT

# The tools the scripts use, without a nix the host may have.
sysbin=$shared/bin
mkdir "$sysbin"
for tool in bash env sed grep cat cp mv rm mkdir mktemp dirname id stat chmod \
  sha256sum tar xz cut ls touch python3 openssl base64 sort cmp diff jq paste; do
  ln -s "$(command -v "$tool")" "$sysbin/$tool"
done
