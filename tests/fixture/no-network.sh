# Fails when a network interface other than lo is visible. The builder of the
# fixture's check, and run on the runner itself to show that it can fail. In
# the Nix sandbox, /bin/sh is a minimal busybox: only shell builtins.
while read -r name _rest; do
  case $name in
    Inter-\| | face | lo:*) ;;
    *)
      echo "network interface $name is visible"
      exit 1
      ;;
  esac
done </proc/net/dev
echo "${nonce-}" >"${out:-/dev/null}"
