# shellcheck shell=bash disable=SC2154,SC2034 # shared with tests/harness
# Unit tests of scripts/step/configure-token.sh.

setup_action
run "token: written for the user only" ok step/configure-token.sh TOKEN=ghs_abc
expect_file "$work/home/.config/nix/nix.conf" "access-tokens = github.com=ghs_abc"
expect_mode "$work/home/.config/nix/nix.conf" 600
finish

setup_action
mkdir -p "$work/xdg"
run "token: XDG_CONFIG_HOME" ok step/configure-token.sh TOKEN=ghs_abc XDG_CONFIG_HOME="$work/xdg"
expect_file "$work/xdg/nix/nix.conf" "access-tokens = github.com=ghs_abc"
finish

setup_action
mkdir -p "$work/home/.config/nix"
echo "accept-flake-config = true" >"$work/home/.config/nix/nix.conf"
run "token: does not overwrite a conf it did not write" fail step/configure-token.sh TOKEN=ghs_abc
expect_file "$work/home/.config/nix/nix.conf" "accept-flake-config = true"
finish

setup_action
run_with_job_path "token: no tools of the job PATH" configure-token TOKEN=ghs_abc
finish
