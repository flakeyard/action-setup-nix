#!/usr/bin/env bash
# Usage: check-tarball.sh TARBALL
#
# Checks that every store path in a Nix release tarball is in cache.nixos.org
# with the same NAR hash and size, signed by cache.nixos.org-1. A path that the
# cache does not have is reported; a mismatch or a bad signature fails.
set -euo pipefail
export LC_ALL=C

tarball=$1
cache=https://cache.nixos.org
key=6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

# The Ed25519 key as a DER SubjectPublicKeyInfo, for openssl.
{
  printf '\x30\x2a\x30\x05\x06\x03\x2b\x65\x70\x03\x21\x00'
  base64 -d <<<"$key"
} >"$work/key.der"

tar --extract --xz --file "$tarball" --directory "$work" --wildcards '*/.reginfo'
reginfo=("$work"/*/.reginfo)

# narinfo FIELD FILE: prints the value of FIELD in the narinfo FILE.
narinfo() { sed -n "s/^$1: //p" "$2"; }

checked=0 missing=0
# .reginfo: path, NAR hash, NAR size, deriver, number of references, references.
while IFS= read -r path && IFS= read -r nar_hash && IFS= read -r nar_size &&
  IFS= read -r _deriver && IFS= read -r count; do
  for ((i = 0; i < count; i++)); do IFS= read -r _; done
  base=${path#/nix/store/}
  info=$work/${base%%-*}.narinfo
  status=$(curl --proto '=https' --fail-with-body --silent --show-error \
    --retry 3 --output "$info" --write-out '%{http_code}' \
    "$cache/${base%%-*}.narinfo" || true)
  if [[ $status == 404 ]]; then
    echo "not in $cache: $path"
    missing=$((missing + 1))
    continue
  fi
  [[ $status == 200 ]] || {
    echo "error: $cache returned HTTP $status for $path" >&2
    exit 1
  }
  if [[ $(narinfo StorePath "$info") != "$path" ||
  $(narinfo NarHash "$info") != "$nar_hash" ||
  $(narinfo NarSize "$info") != "$nar_size" ]]; then
    echo "error: $path in the tarball differs from $cache" >&2
    exit 1
  fi
  refs=()
  read -r -a refs <<<"$(narinfo References "$info")"
  fingerprint="1;$path;$nar_hash;$nar_size;"
  sep=""
  for ref in "${refs[@]}"; do
    fingerprint+="$sep/nix/store/$ref"
    sep=,
  done
  printf '%s' "$fingerprint" >"$work/fingerprint"
  signed=false
  while IFS= read -r sig; do
    [[ $sig == cache.nixos.org-1:* ]] || continue
    base64 -d <<<"${sig#*:}" >"$work/sig"
    if openssl pkeyutl -verify -pubin -keyform DER -inkey "$work/key.der" \
      -rawin -in "$work/fingerprint" -sigfile "$work/sig" >/dev/null 2>&1; then
      signed=true
    fi
  done < <(narinfo Sig "$info")
  $signed || {
    echo "error: no valid signature of cache.nixos.org-1 for $path" >&2
    exit 1
  }
  checked=$((checked + 1))
done <"${reginfo[0]}"

echo "$checked store paths match $cache and its signatures; $missing not in the cache."
((checked > 0))
