# shellcheck shell=bash disable=SC2154,SC2034 # shared with tests/lib.sh
# Unit tests of scripts/lib/nix-conf.sh, step/install.sh and
# step/configure-token.sh.

# --- nix-conf.sh ------------------------------------------------------------

setup
run "nix-conf: defaults" ok lib/nix-conf.sh
expect message "sandbox = true"
expect message "sandbox-fallback = false"
expect message "substituters = https://cache.nixos.org/"
expect message "accept-flake-config = false"
expect no-message "extra-substituters"
expect no-message "extra-trusted-public-keys"
finish

setup
run "nix-conf: extra caches on one line each" ok lib/nix-conf.sh \
  SUBSTITUTERS=$'https://a.example.org\n https://b.example.org' KEYS="$key"
expect message "extra-substituters = https://a.example.org https://b.example.org"
expect message "extra-trusted-public-keys = $key"
finish

# --- install.sh -------------------------------------------------------------

setup
run "install: installs the pinned tarball" ok step/install.sh \
  NIX_USER_COUNT=1 NIX_CONFIG="sandbox = false" NIX_VERSION=9.9.9 \
  NIX_BASE_URL=https://evil.test
expect call "curl https://example.test/nix/nix-$NIX_VERSION/nix-$NIX_VERSION-x86_64-linux.tar.xz"
expect call "install --daemon --yes --no-channel-add --nix-extra-conf-file"
expect path "$fs/nix/var/nix/profiles/default/bin"
if [[ -n $current ]] && grep -qE '^(NIX_|CALLS|FIXTURES|GITHUB_)' "$work/installer-env"; then
  report "the installer got the job environment: $(grep -E '^(NIX_|CALLS|FIXTURES|GITHUB_)' "$work/installer-env")"
fi
expect file "$fs/etc/nix/nix.conf" "$("$action/scripts/lib/nix-conf.sh")"$'\n'"build-users-group = nixbld"
[[ -z $current || -z $(ls -A "$work/temp") ]] || report "temporary files left: $(ls -A "$work/temp")"
finish

setup
fake_tarball "$NIX_VERSION" aarch64-linux
pin_tarball "$NIX_VERSION" aarch64-linux
run "install: arm64 tarball" ok step/install.sh RUNNER_ARCH=ARM64
expect call "curl https://example.test/nix/nix-$NIX_VERSION/nix-$NIX_VERSION-aarch64-linux.tar.xz"
finish

setup
echo tampered >>"$(tarball_fixture "$NIX_VERSION" x86_64-linux)"
run "install: hash mismatch installs nothing" fail step/install.sh
expect message "::error::SHA-256 of https://example.test/nix/nix-$NIX_VERSION/nix-$NIX_VERSION-x86_64-linux.tar.xz is"
expect no-call "install --daemon"
[[ -z $current || ! -e $fs/etc/nix ]] || report "nix.conf was written"
finish

setup
rm "$(tarball_fixture "$NIX_VERSION" x86_64-linux)"
run "install: download failure" fail step/install.sh
expect no-call "install --daemon"
finish

setup
run "install: extra caches reach nix.conf" ok step/install.sh \
  SUBSTITUTERS="https://cache.example.org" KEYS="$key"
expect file "$fs/etc/nix/nix.conf" "$(SUBSTITUTERS="https://cache.example.org" KEYS="$key" "$action/scripts/lib/nix-conf.sh")"$'\n'"build-users-group = nixbld"
finish

# --- configure-token.sh -----------------------------------------------------

setup
run "token: written for the user only" ok step/configure-token.sh TOKEN=ghs_abc
expect file "$work/home/.config/nix/nix.conf" "access-tokens = github.com=ghs_abc"
expect mode "$work/home/.config/nix/nix.conf" 600
finish

setup
mkdir -p "$work/xdg"
run "token: XDG_CONFIG_HOME" ok step/configure-token.sh TOKEN=ghs_abc XDG_CONFIG_HOME="$work/xdg"
expect file "$work/xdg/nix/nix.conf" "access-tokens = github.com=ghs_abc"
finish

setup
mkdir -p "$work/home/.config/nix"
echo "accept-flake-config = true" >"$work/home/.config/nix/nix.conf"
run "token: does not overwrite a conf it did not write" fail step/configure-token.sh TOKEN=ghs_abc
expect file "$work/home/.config/nix/nix.conf" "accept-flake-config = true"
finish

# --- install.sh: failures -----------------------------------------------------

setup
sed -i 's|^#!/bin/bash$|#!/bin/bash\nexit 3|' "$work/tarball/nix-$NIX_VERSION-x86_64-linux/install"
repack_tarball "$NIX_VERSION" x86_64-linux
pin_tarball "$NIX_VERSION" x86_64-linux
run "install: installer failure" fail step/install.sh
expect message "::error::The Nix installer failed"
[[ -z $current || ! -s $work/path ]] || report "PATH was extended: $(cat "$work/path")"
[[ -z $current || -z $(ls -A "$work/temp") ]] || report "temporary files left"
finish
