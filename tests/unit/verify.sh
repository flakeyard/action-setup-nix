# shellcheck shell=bash disable=SC2154,SC2034 # shared with tests/lib.sh
# Unit tests of scripts/step/verify.sh.

# install NAME [VAR=VALUE...]: install and store a token like the action does.
install() {
  run "$1 (install)" ok step/install.sh "${@:2}"
  run "$1 (token)" ok step/configure-token.sh TOKEN=ghs_abc
  current=""
}

# --- verify.sh --------------------------------------------------------------

setup
install "verify: ok"
run "verify: ok" ok step/verify.sh NIX_CONFIG="sandbox = false"
expect output "nix-version=$NIX_VERSION"
finish

setup
install "verify: extra caches" SUBSTITUTERS="https://cache.example.org" KEYS="$key"
run "verify: extra caches" ok step/verify.sh SUBSTITUTERS="https://cache.example.org" KEYS="$key"
finish

setup
install "verify: inputs differ from the installation" SUBSTITUTERS="https://cache.example.org" KEYS="$key"
run "verify: inputs differ from the installation" fail step/verify.sh
expect message "Unexpected line"
finish

setup
fake_tarball "$NIX_VERSION" x86_64-linux 0.0.1
pin_tarball "$NIX_VERSION" x86_64-linux
install "verify: wrong version"
run "verify: wrong version" fail step/verify.sh
expect message "Installed 'nix (Nix) 0.0.1', expected Nix $NIX_VERSION"
finish

setup
install "verify: daemon down"
touch "$work/daemon-down"
run "verify: daemon down" fail step/verify.sh
expect message "The Nix daemon does not answer"
finish

setup
install "verify: extra line"
echo "trusted-users = runner" >>"$fs/etc/nix/nix.conf"
run "verify: extra line in nix.conf" fail step/verify.sh
expect message "Unexpected line in $fs/etc/nix/nix.conf: trusted-users = runner"
finish

setup
install "verify: sandbox off"
sed -i 's/^sandbox = true/sandbox = false/' "$fs/etc/nix/nix.conf"
run "verify: changed setting" fail step/verify.sh
expect message "does not start with the settings of this action"
finish

setup
run "verify: nothing installed" fail step/verify.sh
expect message "::error::$fs/nix/var/nix/profiles/default/bin/nix was not installed."
finish

setup
install "verify: no nix.conf"
rm "$fs/etc/nix/nix.conf"
run "verify: no nix.conf" fail step/verify.sh
expect message "::error::$fs/etc/nix/nix.conf was not installed."
finish
