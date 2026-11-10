# shellcheck shell=bash disable=SC2034 # variables for the unit tests
# The environment of the unit tests, sourced first by tests/run.sh: files
# shared by all tests and the tools of the scripts.
export LC_ALL=C

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
key=cache.example.org-1:$(printf 'k%.0s' {1..43})=

# shellcheck source-path=SCRIPTDIR source=../../versions.sh
source "$root/versions.sh"
# shellcheck source-path=SCRIPTDIR source=../../scripts/lib/tarball.sh
source "$root/scripts/lib/tarball.sh"

# Files shared by all tests, removed at the end.
shared=$(mktemp -d)
trap 'rm -rf -- "$shared"' EXIT

# The tools the scripts and the stubs use, without a nix the host may have;
# touch for the tests that code from a tarball does not run.
sysbin=$shared/bin
mkdir "$sysbin"
for tool in bash env sed grep cat cp mv rm mkdir mktemp dirname id chmod \
  sha256sum tar xz touch python3 openssl cmp diff; do
  ln -s "$(command -v "$tool")" "$sysbin/$tool"
done
