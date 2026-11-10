# shellcheck shell=bash
# Where things are on the runner. Sourced after env.sh, not run.

# nix_system: prints the Nix system of the runner; fails on other runners.
nix_system() {
  case ${RUNNER_ARCH-} in
    X64) echo x86_64-linux ;;
    ARM64) echo aarch64-linux ;;
    *) return 1 ;;
  esac
}

# user_conf: prints the path of the runner user's nix.conf.
user_conf() {
  echo "${XDG_CONFIG_HOME:-$HOME/.config}/nix/nix.conf"
}

# nix_bin: prints the path of the installed nix.
nix_bin() {
  echo "$ROOT/nix/var/nix/profiles/default/bin/nix"
}
