# shellcheck shell=bash
# Where things are on the runner. Sourced after env.sh, not run; also by
# step/unsupported-os.sh, on any runner, for unsupported_runner.

# unsupported_runner RUNNER: prints the error for RUNNER, such as macOS or
# Linux/X86, which the action does not support.
unsupported_runner() {
  local runner=$1
  echo "Unsupported runner $runner: use a GitHub-hosted Linux runner on X64 or ARM64, such as ubuntu-24.04 or ubuntu-24.04-arm."
}

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
