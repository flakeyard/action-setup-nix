#!/usr/bin/env bash
# Updates a copy of the action from the previous Nix release to the pinned one
# with scripts/update/nix.sh, on the real release tarballs. The result must
# equal the committed versions.sh and README.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
# shellcheck source-path=SCRIPTDIR source=../../versions.sh
source versions.sh

tags=$(git ls-remote --tags https://github.com/NixOS/nix |
  sed -n 's|.*refs/tags/\([0-9]*\.[0-9]*\.[0-9]*\)$|\1|p')
previous=$(printf '%s\n' "$tags" "$NIX_VERSION" | sort -uV |
  grep -x -B 1 -F -- "$NIX_VERSION" | head -n 1)
if [[ -z $previous || $previous == "$NIX_VERSION" ]]; then
  echo "::error::No Nix release before $NIX_VERSION among the tags of NixOS/nix."
  exit 1
fi
echo "Updating a copy from Nix $previous to $NIX_VERSION."

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cp -R scripts versions.sh README.md "$work/"
sed -i "s/^NIX_VERSION=.*/NIX_VERSION=$previous/" "$work/versions.sh"
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
