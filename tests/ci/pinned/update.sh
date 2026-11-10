#!/usr/bin/env bash
# Updates a copy of the action from the release that the pinned one replaced,
# PREVIOUS_NIX_VERSION, with scripts/update/nix.sh, on the real release
# tarballs. The result must equal the committed versions.sh and README.
# Inputs (environment): SHELL_LIB.
set -euo pipefail
# shellcheck source=/dev/null # the library, from SHELL_LIB
source "$SHELL_LIB/report.sh"
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.."
# shellcheck source-path=SCRIPTDIR source=../../../versions.sh
source versions.sh
# shellcheck source-path=SCRIPTDIR source=../../../scripts/lib/tarball.sh
source scripts/lib/tarball.sh

# A SHA-256 as releases.nixos.org publishes it.
SHA256_RE='^[0-9a-f]{64}$'

previous=$PREVIOUS_NIX_VERSION
echo "Updating a copy from Nix $previous to $NIX_VERSION."

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cp -R scripts versions.sh README.md "$work/"
# The update must also record the release it replaces. The copy is set back
# with patterns of its own, not those of scripts/update/nix.sh: a pattern that
# matched nothing would then leave the copy as committed in both, and the
# diffs below would pass.
sed -i -e "s/^NIX_VERSION=.*/NIX_VERSION=$previous/" \
  -e "s/^PREVIOUS_NIX_VERSION=.*/PREVIOUS_NIX_VERSION=/" "$work/versions.sh"
# scripts/update/nix.sh checks the previous tarballs against these hashes
# before it compares their installer scripts.
for system in "${SYSTEMS[@]}"; do
  hash=$("${HTTPS_CURL[@]}" "$(tarball_url "$previous" "$system").sha256")
  [[ $hash =~ $SHA256_RE ]] ||
    fail "Invalid published SHA-256 of Nix $previous for $system: $hash"
  var=$(pin_var "$system")
  sed -i "s/^$var=.*/$var=$hash/" "$work/versions.sh"
done
sed -i "s/This release installs Nix [0-9.]*[0-9]\./This release installs Nix $previous./" \
  "$work/README.md"

"$work/scripts/update/nix.sh" "$NIX_VERSION"
diff -u versions.sh "$work/versions.sh"
diff -u README.md "$work/README.md"
echo "The update from $previous reproduces the pin of $NIX_VERSION."
