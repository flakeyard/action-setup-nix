{
  description = "Fixture of the CI of action-setup-nix: checks that run in the sandbox.";

  # Must be ignored: accept-flake-config is off and the runner user is not
  # trusted.
  nixConfig.extra-substituters = [ "https://untrusted.invalid" ];

  outputs =
    { self }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      # Written by the CI before the check, so that the result is never
      # substituted from a cache and the check really builds.
      nonce = builtins.readFile ./nonce;
      sandbox =
        system:
        derivation {
          name = "sandbox";
          inherit system nonce;
          # The sandbox shell is a minimal busybox: only shell builtins.
          builder = "/bin/sh";
          args = [
            "-c"
            ''
              while read -r name rest; do
                case $name in
                  Inter-\| | face | lo:*) ;;
                  *)
                    echo "network interface $name is visible in the sandbox"
                    exit 1
                    ;;
                esac
              done </proc/net/dev
              echo "$nonce" >"$out"
            ''
          ];
        };
    in
    {
      checks = builtins.listToAttrs (
        map (system: {
          name = system;
          value.sandbox = sandbox system;
        }) systems
      );
    };
}
