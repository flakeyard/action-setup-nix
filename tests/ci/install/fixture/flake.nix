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
          builder = "/bin/sh";
          args = [ ./no-network.sh ];
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
