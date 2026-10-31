#!/usr/bin/env bash
# Downloads the pinned Nix release tarball, verifies its hash and runs its
# installer in daemon mode with the settings of lib/nix-conf.sh.
#
# Inputs (environment): SUBSTITUTERS, KEYS, RUNNER_ARCH, RUNNER_TEMP,
# GITHUB_PATH.
set -euo pipefail
lib=$(dirname -- "${BASH_SOURCE[0]}")/../lib
# shellcheck source-path=SCRIPTDIR source=../lib/env.sh
source "$lib/env.sh"
# shellcheck source-path=SCRIPTDIR source=../lib/runner.sh
source "$lib/runner.sh"

system=$(nix_system)
hash_var=NIX_SHA256_${system//-/_}
expected=${!hash_var}
name=nix-$NIX_VERSION-$system
url=$NIX_BASE_URL/nix-$NIX_VERSION/$name.tar.xz

work=$(mktemp -d "$RUNNER_TEMP/setup-nix.XXXXXX")
trap 'rm -rf -- "$work"' EXIT

echo "Downloading $url"
curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
  --retry 3 --connect-timeout 20 --max-time 600 \
  --output "$work/nix.tar.xz" "$url"

actual=$(sha256sum "$work/nix.tar.xz")
actual=${actual%% *}
if [[ $actual != "$expected" ]]; then
  printf '::error::SHA-256 of %s is %s, expected %s; nothing was installed.\n' \
    "$url" "$actual" "$expected"
  exit 1
fi

tar --extract --xz --file "$work/nix.tar.xz" --directory "$work"
"$lib/nix-conf.sh" >"$work/nix.conf"

# The installer reads NIX_* and other variables, which earlier steps can set
# for the whole job; it gets only what it needs.
user=$(id -un)
env -i PATH="$SYSTEM_PATH" HOME="$HOME" USER="$user" \
  LC_ALL=C TMPDIR="$work" \
  "$work/$name/install" --daemon --yes --no-channel-add \
  --nix-extra-conf-file "$work/nix.conf" ||
  {
    echo "::error::The Nix installer failed; see its output above."
    exit 1
  }

dirname -- "$(nix_bin)" >>"$GITHUB_PATH"
