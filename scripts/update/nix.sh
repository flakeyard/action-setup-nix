#!/usr/bin/env bash
# Usage: scripts/update/nix.sh VERSION
#
# Pins the Nix release VERSION in versions.sh. Downloads the tarball of every
# system, checks it against the published hash and with check-tarball.py, shows
# how its installer scripts differ from the pinned release, and writes
# versions.sh only when every system passed, with the replaced release as
# PREVIOUS_NIX_VERSION. Run with the pinned version, it checks the pin and
# changes nothing; the CI does that.
set -euo pipefail
shopt -s inherit_errexit
export LC_ALL=C

VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+$'

version=${1:?usage: scripts/update/nix.sh VERSION}
[[ $version =~ $VERSION_RE ]] || {
  echo "error: expected a version such as 2.35.4, got '$version'" >&2
  exit 2
}
here=$(dirname -- "${BASH_SOURCE[0]}")
versions=$here/../../versions.sh
readme=$here/../../README.md
# shellcheck source-path=SCRIPTDIR source=../../versions.sh
source "$versions"
# shellcheck source-path=SCRIPTDIR source=../lib/tarball.sh
source "$here/../lib/tarball.sh"

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

fail() {
  echo "error: $1" >&2
  exit 1
}

# download VERSION SYSTEM: downloads a release tarball to $work and prints its
# path.
download() {
  local url file
  url=$(tarball_url "$@")
  file=$work/${url##*/}
  echo "Downloading $url" >&2
  "${HTTPS_CURL[@]}" --output "$file" "$url"
  echo "$file"
}

# published_sha256 VERSION SYSTEM: prints the SHA-256 that the release
# publishes for its tarball.
published_sha256() {
  local url
  url=$(tarball_url "$@")
  "${HTTPS_CURL[@]}" "$url.sha256"
}

# with_pin NAME VALUE: prints versions.sh from stdin with NAME set to VALUE.
with_pin() {
  local name=$1 value=$2
  sed -e "s/^$name=.*/$name=$value/"
}

# check_tarball_hash FILE EXPECTED NAME SOURCE: fails unless FILE has the
# SHA-256 EXPECTED. NAME names FILE and SOURCE says where EXPECTED is from.
check_tarball_hash() {
  local file=$1 expected=$2 name=$3 source=$4 actual
  actual=$(sha256_of "$file")
  [[ $actual == "$expected" ]] ||
    fail "$name has SHA-256 $actual, $source $expected"
}

# unpack_installer TARBALL DIR TOP: unpacks TARBALL into DIR without TOP/store,
# its top-level store.
unpack_installer() {
  local tarball=$1 dir=$2 top=$3
  mkdir -p "$dir"
  tar --extract --xz --file "$tarball" --directory "$dir" \
    --anchored --exclude "$top/store"
}

# show_installer_changes SYSTEM TARBALL: shows how the installer scripts of
# TARBALL differ from those of the pinned release, which no signature covers.
show_installer_changes() {
  local system=$1 tarball=$2 pinned expected old new status=0
  old=$(tarball_name "$NIX_VERSION" "$system")
  new=$(tarball_name "$version" "$system")
  pinned=$(download "$NIX_VERSION" "$system")
  expected=$(pinned_sha256 "$system")
  check_tarball_hash "$pinned" "$expected" "the pinned tarball for $system" pinned
  unpack_installer "$pinned" "$work/old" "$old"
  unpack_installer "$tarball" "$work/new" "$new"
  echo "Changes of the installer scripts for $system since $NIX_VERSION:"
  # Status 1 means differences; more is an error of diff.
  diff -ruN --exclude .reginfo "$work/old/$old" "$work/new/$new" || status=$?
  ((status <= 1)) || fail "cannot compare the installer scripts for $system"
  rm -rf -- "$work/old" "$work/new"
}

# check_system SYSTEM: checks the tarball of $version for SYSTEM and pins its
# hash in $script.
check_system() {
  local system=$1 tarball published
  tarball=$(download "$version" "$system")
  published=$(published_sha256 "$version" "$system")
  check_tarball_hash "$tarball" "$published" "the tarball for $system" published
  "$here/check-tarball.py" "$tarball"
  if [[ $version != "$NIX_VERSION" ]]; then
    show_installer_changes "$system" "$tarball"
  fi
  script=$(with_pin "$(pin_var "$system")" "$published" <<<"$script")
}

update_readme() {
  sed -i -e "s/This release installs Nix [0-9.]*[0-9]\./This release installs Nix $version./" "$readme"
}

print_commit_advice() {
  echo "Pinned Nix $version. Review the changes of the installer scripts above,"
  echo "then commit as fix(deps) for a new patch version and as feat(deps) for a"
  echo "new minor version, or as a breaking change if the release notes of Nix"
  echo "list incompatible changes."
}

# pin_version: pins $version in $script and keeps the release it replaces.
pin_version() {
  if [[ $version != "$NIX_VERSION" ]]; then
    script=$(with_pin PREVIOUS_NIX_VERSION "$NIX_VERSION" <<<"$script")
  fi
  script=$(with_pin NIX_VERSION "$version" <<<"$script")
}

script=$(<"$versions")
for system in "${SYSTEMS[@]}"; do
  check_system "$system"
done
pin_version

printf '%s\n' "$script" >"$work/versions.sh"
if cmp -s "$work/versions.sh" "$versions"; then
  echo "versions.sh already pins Nix $version with these hashes."
  exit 0
fi
mv -- "$work/versions.sh" "$versions"
update_readme
print_commit_advice
