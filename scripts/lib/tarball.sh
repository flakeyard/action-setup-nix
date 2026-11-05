# shellcheck shell=bash
# The release tarballs of Nix: the systems, where the tarballs are, how they
# are fetched and how their hashes are pinned in versions.sh. Sourced after
# versions.sh by step/install.sh, update/nix.sh and the tests, not run.

# shellcheck disable=SC2034 # used by update/nix.sh and the tests
SYSTEMS=(x86_64-linux aarch64-linux)

# curl over https only, also after redirects. https-curl-args holds one
# argument per line, shared with update/check-tarball.py, which follows no
# redirects.
mapfile -t HTTPS_CURL_ARGS <"${BASH_SOURCE[0]%/*}/https-curl-args"
# shellcheck disable=SC2034 # used by the scripts that source this file
HTTPS_CURL=(curl "${HTTPS_CURL_ARGS[@]}" --proto-redir '=https' --location --fail)

# tarball_name VERSION SYSTEM: prints the name of a release tarball without
# .tar.xz, which is also the name of its top-level directory.
tarball_name() {
  local version=$1 system=$2
  echo "nix-$version-$system"
}

# tarball_url VERSION SYSTEM: prints the URL of a release tarball.
tarball_url() {
  local version=$1 system=$2
  echo "$NIX_BASE_URL/nix-$version/$(tarball_name "$version" "$system").tar.xz"
}

# pin_var SYSTEM: prints the name of the variable that pins the hash of the
# tarball for SYSTEM.
pin_var() {
  local system=$1
  echo "NIX_SHA256_${system//-/_}"
}

# pinned_sha256 SYSTEM: prints the pinned hash of the tarball for SYSTEM.
pinned_sha256() {
  local system=$1 var
  var=$(pin_var "$system")
  echo "${!var}"
}

# sha256_of FILE: prints the SHA-256 of FILE.
sha256_of() {
  local file=$1 sum
  sum=$(sha256sum -- "$file")
  echo "${sum%% *}"
}
