#!/usr/bin/env bash
# Usage: scripts/update-nix.sh VERSION
#
# Pins the Nix release VERSION in versions.sh. Downloads the tarball of every
# system, checks it against the published hash and with check-tarball.py, shows
# how its installer scripts differ from the pinned release, and writes
# versions.sh only when every system passed. Run with the pinned version, it
# checks the pin and changes nothing; the CI does that.
set -euo pipefail
shopt -s inherit_errexit
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

# fetch VERSION SYSTEM: downloads a release tarball to $work and prints its path.
fetch() {
  local url=$NIX_BASE_URL/nix-$1/nix-$1-$2.tar.xz file=$work/nix-$1-$2.tar.xz
  echo "Downloading $url" >&2
  curl --proto '=https' --fail --silent --show-error --location --retry 3 \
    --output "$file" "$url"
  echo "$file"
}

script=$(<"$versions")
for system in x86_64-linux aarch64-linux; do
  var=NIX_SHA256_${system//-/_}
  tarball=$(fetch "$version" "$system")
  published=$(curl --proto '=https' --fail --silent --show-error --location \
    --retry 3 "$NIX_BASE_URL/nix-$version/nix-$version-$system.tar.xz.sha256")
  actual=$(sha256sum "$tarball")
  actual=${actual%% *}
  [[ $actual == "$published" ]] || {
    echo "error: the tarball for $system has SHA-256 $actual, published $published" >&2
    exit 1
  }
  "$here/check-tarball.py" "$tarball"

  # The installer scripts are not signed: show what changed for review.
  if [[ $version != "$NIX_VERSION" ]]; then
    pinned=$(fetch "$NIX_VERSION" "$system")
    pinned_actual=$(sha256sum "$pinned")
    pinned_actual=${pinned_actual%% *}
    [[ $pinned_actual == "${!var}" ]] || {
      echo "error: the pinned tarball for $system has SHA-256 $pinned_actual, pinned ${!var}" >&2
      exit 1
    }
    mkdir -p "$work/old" "$work/new"
    tar --extract --xz --file "$pinned" --directory "$work/old" \
      --anchored --exclude "nix-$NIX_VERSION-$system/store"
    tar --extract --xz --file "$tarball" --directory "$work/new" \
      --anchored --exclude "nix-$version-$system/store"
    echo "Changes of the installer scripts for $system since $NIX_VERSION:"
    # Status 1 means differences; more is an error of diff.
    diff_status=0
    diff -ruN --exclude .reginfo "$work/old/nix-$NIX_VERSION-$system" \
      "$work/new/nix-$version-$system" || diff_status=$?
    ((diff_status <= 1)) || {
      echo "error: cannot compare the installer scripts for $system" >&2
      exit 1
    }
    rm -rf -- "$work/old" "$work/new"
  fi

  # shellcheck disable=SC2001 # replaces whole lines
  script=$(sed -e "s/^$var=.*/$var=$actual/" <<<"$script")
done
# shellcheck disable=SC2001 # replaces whole lines
script=$(sed -e "s/^NIX_VERSION=.*/NIX_VERSION=$version/" <<<"$script")

printf '%s\n' "$script" >"$work/versions.sh"
if cmp -s "$work/versions.sh" "$versions"; then
  echo "versions.sh already pins Nix $version with these hashes."
  exit 0
fi
mv -- "$work/versions.sh" "$versions"
readme=$here/../README.md
if [[ -f $readme ]]; then
  sed -i -e "s/This release installs Nix [0-9.]*[0-9]\./This release installs Nix $version./" "$readme"
fi
echo "Pinned Nix $version. Review the changes of the installer scripts above,"
echo "then commit as fix(deps) for a new patch version and as feat(deps) for a"
echo "new minor version, or as a breaking change if the release notes of Nix"
echo "list incompatible changes."
