#!/usr/bin/env bash
# Updates a copy of the action from the release that the pinned one replaced,
# PREVIOUS_NIX_VERSION, with scripts/update/nix.sh, on the real release
# tarballs. The result must equal the committed versions.sh and README.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.."
# shellcheck source-path=SCRIPTDIR source=../../../versions.sh
source versions.sh

previous=$PREVIOUS_NIX_VERSION
echo "Updating a copy from Nix $previous to $NIX_VERSION."

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cp -R scripts versions.sh README.md "$work/"
# The update must also record the release it replaces.
sed -i -e "s/^NIX_VERSION=.*/NIX_VERSION=$previous/" \
  -e "s/^PREVIOUS_NIX_VERSION=.*/PREVIOUS_NIX_VERSION=/" "$work/versions.sh"
# scripts/update/nix.sh checks the previous tarballs against these hashes
# before it compares their installer scripts.
for system in x86_64-linux aarch64-linux; do
  hash=$(curl --proto '=https' --fail --silent --show-error --location --retry 3 \
    "$NIX_BASE_URL/nix-$previous/nix-$previous-$system.tar.xz.sha256")
  [[ $hash =~ ^[0-9a-f]{64}$ ]] || {
    echo "::error::Invalid published SHA-256 of Nix $previous for $system: $hash"
    exit 1
  }
  var=NIX_SHA256_${system//-/_}
  sed -i "s/^$var=.*/$var=$hash/" "$work/versions.sh"
done
sed -i "s/This release installs Nix [0-9.]*[0-9]\./This release installs Nix $previous./" \
  "$work/README.md"

"$work/scripts/update/nix.sh" "$NIX_VERSION"
diff -u versions.sh "$work/versions.sh"
diff -u README.md "$work/README.md"
echo "The update from $previous reproduces the pin of $NIX_VERSION."
