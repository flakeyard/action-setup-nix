#!/usr/bin/env bash
# Usage: scripts/update-nix.sh VERSION
#
# For maintainers: pins the Nix release VERSION in versions.sh. Downloads the
# tarball of every system, checks it against the published hash and against
# the signed store paths in cache.nixos.org, and writes the hashes.
set -euo pipefail
export LC_ALL=C

version=${1:?usage: update-nix.sh VERSION}
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "error: expected a version such as 2.35.4, got '$version'" >&2
  exit 2
}
here=$(dirname -- "${BASH_SOURCE[0]}")
versions=$here/../versions.sh
# shellcheck source-path=SCRIPTDIR source=../versions.sh
source "$versions"

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

for system in x86_64-linux aarch64-linux; do
  url=$NIX_BASE_URL/nix-$version/nix-$version-$system.tar.xz
  echo "Downloading $url"
  curl --proto '=https' --fail --silent --show-error --location --retry 3 \
    --output "$work/$system.tar.xz" "$url"
  published=$(curl --proto '=https' --fail --silent --show-error --location \
    --retry 3 "$url.sha256")
  actual=$(sha256sum "$work/$system.tar.xz")
  actual=${actual%% *}
  [[ $actual == "$published" ]] || {
    echo "error: $url has SHA-256 $actual, published $published" >&2
    exit 1
  }
  "$here/check-tarball.sh" "$work/$system.tar.xz"
  sed -i -e "s/^NIX_SHA256_${system//-/_}=.*/NIX_SHA256_${system//-/_}=$actual/" "$versions"
done
sed -i -e "s/^NIX_VERSION=.*/NIX_VERSION=$version/" "$versions"

echo "Pinned Nix $version. Commit it as fix(deps) for a new patch version and"
echo "as feat(deps) for a new minor version, or as a breaking change if the"
echo "release notes of Nix list incompatible changes."
