#!/usr/bin/env bash
# Usage: check-tarball.sh TARBALL
#
# Checks a Nix release tarball against cache.nixos.org: every store path in it
# must be in the cache, signed by cache.nixos.org-1, with the NAR hash, size
# and references of the store path's contents in the tarball, and the tarball
# must contain no other store paths. The installer scripts next to the store
# are not covered by any signature; update-nix.sh shows their changes.
#
# Needs curl, openssl, python3, tar and xz; not Nix.
set -euo pipefail
shopt -s inherit_errexit
export LC_ALL=C

cache=https://cache.nixos.org
key=cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=

tarball=${1:?usage: check-tarball.sh TARBALL}
here=$(dirname -- "${BASH_SOURCE[0]}")
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

fail() {
  echo "error: $1" >&2
  exit 1
}

# The Ed25519 key as a DER SubjectPublicKeyInfo, for openssl.
{
  printf '\x30\x2a\x30\x05\x06\x03\x2b\x65\x70\x03\x21\x00'
  base64 -d <<<"${key#*:}"
} >"$work/key.der"

mkdir "$work/tar"
tar --extract --xz --file "$tarball" --directory "$work/tar"
dirs=("$work"/tar/*/)
((${#dirs[@]} == 1)) || fail "expected one top-level directory in $tarball"
top=${dirs[0]%/}
[[ -f $top/.reginfo && -d $top/store ]] || fail "no .reginfo or store in $tarball"

path_re='^/nix/store/([0-9a-df-np-sv-z]{32}-[A-Za-z0-9+._?=-]+)$'
hash_re='^sha256:[0-9a-df-np-sv-z]{52}$'
number_re='^[0-9]{1,12}$'

# narinfo FIELD FILE: prints the value of FIELD in the narinfo FILE.
narinfo() { sed -n "s/^$1: //p" "$2"; }

checked=0
declare -A listed=()
# .reginfo: path, NAR hash, NAR size, deriver, number of references, references.
# Every field is checked before it is used: the tarball is not trusted yet.
while IFS= read -r path; do
  [[ -n $path ]] || continue
  if ! { IFS= read -r nar_hash && IFS= read -r nar_size &&
    IFS= read -r _deriver && IFS= read -r count; }; then
    fail "truncated .reginfo after $path"
  fi
  [[ $path =~ $path_re ]] || fail "invalid store path in .reginfo: $path"
  name=${BASH_REMATCH[1]}
  [[ $nar_hash =~ $hash_re ]] || fail "invalid NAR hash for $path"
  [[ $nar_size =~ $number_re && $count =~ $number_re ]] ||
    fail "invalid size or reference count for $path"
  refs=()
  for ((i = 0; i < 10#$count; i++)); do
    IFS= read -r ref || fail "truncated references of $path"
    [[ $ref =~ $path_re ]] || fail "invalid reference of $path: $ref"
    refs+=("${BASH_REMATCH[1]}")
  done
  [[ -z ${listed[$name]-} ]] || fail "$path is listed twice"
  listed[$name]=1

  # The contents in the tarball.
  [[ -e $top/store/$name || -L $top/store/$name ]] || fail "$path is not in the tarball"
  read -r actual_hash actual_size < <("$here/nar-hash.py" "$top/store/$name")
  [[ $actual_hash == "$nar_hash" && $actual_size == "$nar_size" ]] ||
    fail "the contents of $path do not match .reginfo"

  # The signed narinfo in the cache.
  info=$work/${name%%-*}.narinfo
  status=$(curl --proto '=https' --silent --show-error --retry 3 \
    --output "$info" --write-out '%{http_code}' \
    "$cache/${name%%-*}.narinfo") || fail "cannot fetch the narinfo of $path"
  [[ $status == 200 ]] || fail "$cache returned HTTP $status for $path"
  cache_refs=()
  read -r -a cache_refs <<<"$(narinfo References "$info")"
  [[ $(narinfo StorePath "$info") == "$path" &&
  $(narinfo NarHash "$info") == "$nar_hash" &&
  $(narinfo NarSize "$info") == "$nar_size" &&
  $(printf '%s\n' "${cache_refs[@]}" | sort) == "$(printf '%s\n' "${refs[@]}" | sort)" ]] ||
    fail "$path in the tarball differs from $cache"

  fingerprint="1;$path;$nar_hash;$nar_size;"
  sep=""
  for ref in "${cache_refs[@]}"; do
    fingerprint+="$sep/nix/store/$ref"
    sep=,
  done
  printf '%s' "$fingerprint" >"$work/fingerprint"
  signed=false
  while IFS= read -r sig; do
    [[ $sig == "${key%%:*}":* ]] || continue
    base64 -d <<<"${sig#*:}" >"$work/sig" 2>/dev/null || continue
    if openssl pkeyutl -verify -pubin -keyform DER -inkey "$work/key.der" \
      -rawin -in "$work/fingerprint" -sigfile "$work/sig" >/dev/null 2>&1; then
      signed=true
    fi
  done < <(narinfo Sig "$info")
  $signed || fail "no valid signature of ${key%%:*} for $path"
  checked=$((checked + 1))
done <"$top/.reginfo"

((checked > 0)) || fail "no store paths in .reginfo"
shopt -s dotglob nullglob
for entry in "$top"/store/*; do
  [[ -n ${listed[${entry##*/}]-} ]] || fail "store/${entry##*/} is not listed in .reginfo"
done

echo "$checked store paths match $cache and its signatures."
