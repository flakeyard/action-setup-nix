# shellcheck shell=bash disable=SC2154,SC2034 # shared with tests/harness
# Unit tests of scripts/update/check-tarball.py.

# A key of a test cache, and names of two store paths.
signing_key=$shared/signing.pem
openssl genpkey -algorithm ed25519 -out "$signing_key" 2>/dev/null
test_key=test-1:$(openssl pkey -in "$signing_key" -pubout -outform DER | tail -c 32 | base64)
dep=$(printf 'a%.0s' {1..32})-dep-1.0
nix=$(printf 'b%.0s' {1..32})-nix-9.0.0

# release_setup: a release tarball whose store paths are in the test cache.
# Change $release, then call pack.
release_setup() {
  setup
  sed -i -e 's|^CACHE_URL = .*|CACHE_URL = "https://example.test/cache"|' \
    -e "s|^CACHE_KEY = .*|CACHE_KEY = \"$test_key\"|" "$action/scripts/update/check-tarball.py"
  release=$work/release/nix-9.0.0-x86_64-linux
  mkdir -p "$release/store/$dep/lib" "$release/store/$nix/bin"
  echo library >"$release/store/$dep/lib/libdep"
  printf '#!/bin/sh\n' >"$release/store/$nix/bin/nix"
  chmod +x "$release/store/$nix/bin/nix"
  ln -s nix "$release/store/$nix/bin/nix-store"
  echo installer >"$release/install"
  reginfo_entry "$dep" >"$release/.reginfo"
  reginfo_entry "$nix" "$dep" >>"$release/.reginfo"
  narinfo "$dep"
  narinfo "$nix" "$dep"
}

# reginfo_entry NAME [REFERENCE...]: the .reginfo lines of a store path.
reginfo_entry() {
  local name=$1
  shift
  printf '/nix/store/%s\n' "$name"
  "$root/scripts/update/check-tarball.py" --nar-hash "$release/store/$name" | tr ' ' '\n'
  printf '\n%s\n' "$#"
  (($#)) && printf '/nix/store/%s\n' "$@"
  return 0
}

# narinfo NAME [REFERENCE...]: a signed narinfo of a store path in the cache.
narinfo() {
  local name=$1 hash size fingerprint refs
  shift
  read -r hash size < <("$root/scripts/update/check-tarball.py" --nar-hash "$release/store/$name")
  refs=""
  (($#)) && refs=$(printf '/nix/store/%s,' "$@")
  fingerprint="1;/nix/store/$name;$hash;$size;${refs%,}"
  printf '%s' "$fingerprint" >"$work/fingerprint"
  openssl pkeyutl -sign -inkey "${sign_with:-$signing_key}" -rawin \
    -in "$work/fingerprint" -out "$work/sig"
  {
    echo "StorePath: /nix/store/$name"
    echo "NarHash: $hash"
    echo "NarSize: $size"
    echo "References: $*"
    echo "Sig: ${test_key%%:*}:$(base64 -w0 <"$work/sig")"
  } >"$work/fixtures/${name%%-*}.narinfo"
}

pack() {
  tar --create --xz --file "$work/release.tar.xz" --directory "$work/release" .
}

release_setup
pack
run "check-tarball: genuine release" ok update/check-tarball.py -- "$work/release.tar.xz"
expect message "2 store paths match https://example.test/cache and its signatures."
finish

release_setup
echo changed >>"$release/store/$nix/bin/nix"
pack
run "check-tarball: changed contents" fail update/check-tarball.py -- "$work/release.tar.xz"
expect message "error: the contents of /nix/store/$nix do not match .reginfo"
finish

release_setup
mkdir "$release/store/$(printf 'c%.0s' {1..32})-extra"
pack
run "check-tarball: unlisted store path" fail update/check-tarball.py -- "$work/release.tar.xz"
expect message "is not listed in .reginfo"
finish

release_setup
reginfo_entry "$dep" >"$release/.reginfo"
reginfo_entry "$nix" "$nix" >>"$release/.reginfo"
pack
run "check-tarball: references differ from the cache" fail update/check-tarball.py -- "$work/release.tar.xz"
expect message "error: /nix/store/$nix in the tarball differs from https://example.test/cache"
finish

release_setup
rm "$work/fixtures/${nix%%-*}.narinfo"
pack
run "check-tarball: not in the cache" fail update/check-tarball.py -- "$work/release.tar.xz"
expect message "returned HTTP 404 for /nix/store/$nix"
finish

release_setup
openssl genpkey -algorithm ed25519 -out "$work/other.pem" 2>/dev/null
sign_with=$work/other.pem narinfo "$nix" "$dep"
pack
run "check-tarball: signed by another key" fail update/check-tarball.py -- "$work/release.tar.xz"
expect message "error: no valid signature of test-1 for /nix/store/$nix"
finish

release_setup
printf '/nix/store/%s\nsha256:%s\n1\n\n%s\n' "$dep" "$(printf '0%.0s' {1..52})" \
  "checked[\$(touch $work/PWNED)]" >"$release/.reginfo"
pack
run "check-tarball: no code from .reginfo" fail update/check-tarball.py -- "$work/release.tar.xz"
expect message "invalid size or reference count"
[[ -z $current || ! -e $work/PWNED ]] || report "code from .reginfo ran"
finish

release_setup
printf '/nix/store/../../x\nsha256:%s\n1\n\n0\n' "$(printf '0%.0s' {1..52})" >"$release/.reginfo"
pack
run "check-tarball: no paths outside the store" fail update/check-tarball.py -- "$work/release.tar.xz"
expect message "invalid store path in .reginfo: /nix/store/../../x"
finish

release_setup
reginfo_entry "$dep" >"$release/.reginfo"
reginfo_entry "$nix" "${dep%.0}.?" >>"$release/.reginfo"
pack
run "check-tarball: references are not patterns" fail update/check-tarball.py -- "$work/release.tar.xz"
expect message "error: /nix/store/$nix in the tarball differs from https://example.test/cache"
finish

setup
printf abc >"$work/file"
run "check-tarball: NAR hash of a file" ok update/check-tarball.py -- --nar-hash "$work/file"
# The value of the earlier nar-hash.py, which checked the real releases.
expect message "sha256:0c2jffsl15masdjkw0akr32jl4daplrwaq81lapg84nqai3ip9qi 120"
finish

setup
run "check-tarball: usage" fail update/check-tarball.py -- "$work/a" "$work/b"
expect message "Usage: check-tarball.py TARBALL"
finish
