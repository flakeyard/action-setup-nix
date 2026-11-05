#!/usr/bin/env bash
# Downloads the pinned Nix release tarball, verifies its hash and runs its
# installer in daemon mode with the settings of lib/nix-conf.sh.
#
# Inputs (environment): SUBSTITUTERS, KEYS, RUNNER_ARCH, RUNNER_TEMP,
# GITHUB_PATH.
set -euo pipefail
# Builtins only until lib/env.sh replaces PATH, which is the job's.
lib=${BASH_SOURCE[0]%/*}/../lib
# shellcheck source-path=SCRIPTDIR source=../lib/env.sh
source "$lib/env.sh"
# shellcheck source-path=SCRIPTDIR source=../lib/runner.sh
source "$lib/runner.sh"
# shellcheck source-path=SCRIPTDIR source=../lib/tarball.sh
source "$lib/tarball.sh"

system=$(nix_system)
expected=$(pinned_sha256 "$system")
name=$(tarball_name "$NIX_VERSION" "$system")
url=$(tarball_url "$NIX_VERSION" "$system")

work=$(mktemp -d "$RUNNER_TEMP/setup-nix.XXXXXX")
trap 'rm -rf -- "$work"' EXIT

echo "Downloading $url"
"${HTTPS_CURL[@]}" --connect-timeout 20 --max-time 600 \
  --output "$work/nix.tar.xz" "$url"

actual=$(sha256_of "$work/nix.tar.xz")
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
