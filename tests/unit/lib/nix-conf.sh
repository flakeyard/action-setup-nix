# shellcheck shell=bash disable=SC2154,SC2034 # shared with tests/harness
# Unit tests of scripts/lib/nix-conf.sh.

# readme_conf: prints the nix.conf block of the README without its indentation.
# shellcheck disable=SC2016 # sed code, not expanded here
readme_conf() {
  sed -n -e '/^  ```ini$/,/^  ```$/{/```/d;s/^  //;p}' "$root/README.md"
}

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
run "nix-conf: the README shows the settings" ok lib/nix-conf.sh
[[ -z $current || $(grep -v '^#' "$work/stdout") == "$(readme_conf)" ]] ||
  report "the README shows other settings: $(diff <(grep -v '^#' "$work/stdout") <(readme_conf))"
finish

setup
run "nix-conf: extra caches on one line each" ok lib/nix-conf.sh \
  SUBSTITUTERS=$'https://a.example.org\n https://b.example.org' KEYS="$key"
expect message "extra-substituters = https://a.example.org https://b.example.org"
expect message "extra-trusted-public-keys = $key"
finish
