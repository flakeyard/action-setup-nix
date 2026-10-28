# action-setup-nix

A GitHub Action that installs Nix on GitHub-hosted Linux runners: a pinned
release of [Nix][nix], verified by its SHA-256, in multi-user mode with the
sandbox on and only the binary caches you name.

## Usage

```yaml
jobs:
  check:
    runs-on: ubuntu-24.04
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@<commit> # v7.0.1
        with:
          persist-credentials: false
      - uses: flakeyard/action-setup-nix@<commit> # v0.1.0
      - run: nix flake check
```

Reference the action by full commit SHA, as above. To use a binary cache besides
`cache.nixos.org`, name it and its key:

```yaml
- uses: flakeyard/action-setup-nix@<commit> # v0.1.0
  with:
    extra-substituters: https://flakeyard.cachix.org
    extra-trusted-public-keys: flakeyard.cachix.org-1:WxHxE1HWLr67hdqhOBRrfWAM408yL6SM3g9++ZaaSzg=
```

## Inputs

- `extra-substituters` (default `""`): binary caches to use besides
  `cache.nixos.org`, separated by whitespace. Each must be an `https` URL
  without user information, query or fragment.
- `extra-trusted-public-keys` (default `""`): public keys of those caches, such
  as `name-1:<base64>`, separated by whitespace. Each must be an Ed25519 key.
  Keys without substituters fail the action. Substituters without keys are
  allowed, with a notice, for mirrors of `cache.nixos.org` that serve paths it
  signed.
- `github-token` (default `${{ github.token }}`): token for fetching flake
  inputs from GitHub, against the API rate limit of 60 requests per hour that
  applies without it. Only letters, digits, underscores, dots and hyphens are
  accepted. Empty disables it.

## Outputs

- `nix-version`: the installed Nix version, such as `2.35.4`.

## Behaviour

- **Nix.** Each release of the action installs one version of Nix from the
  official release tarball of NixOS/nix for the runner's system, verified
  against the SHA-256 recorded in the action. This release installs Nix 2.35.4.
- **Installation.** The steps of the action run the runner's own `bash` and
  tools, without `BASH_ENV`, and the official installer runs in daemon mode with
  a reduced environment, so `PATH`, `NIX_*` and other variables of the job do
  not change the version, the source or the installation. Steps that run before
  the action can still change anything on the runner, through `sudo` too. Later
  steps can rely on:
  - `nix` on `PATH`, from `/nix/var/nix/profiles/default/bin`;
  - a running `nix-daemon`, through systemd;
  - the group `nixbld` with 32 build users;
  - the lines the installer adds to `/etc/bashrc`, `/etc/profile.d/nix.sh`,
    `/etc/zshrc`, `/etc/bash.bashrc` and `/etc/zsh/zshrc`, which load Nix's
    environment in login and interactive shells.
- **Configuration.** `/etc/nix/nix.conf` contains these settings and the
  installer's `build-users-group`, nothing else:

  ```ini
  sandbox = true
  sandbox-fallback = false
  substituters = https://cache.nixos.org/
  trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
  require-sigs = true
  accept-flake-config = false
  extra-experimental-features = nix-command flakes
  max-jobs = auto
  connect-timeout = 10
  fallback = true
  ```

  and, when given, `extra-substituters` and `extra-trusted-public-keys`. The
  action checks the result after the installation.

- **Trust.** `trusted-users` stays `root`, so `nixConfig` of a flake, `--option`
  and tools that write the user's `nix.conf`, such as `cachix use`, cannot add
  caches: the inputs of this action are the only way. This is not a boundary
  against the job itself, which can change anything through `sudo`. Cache URLs
  with a query are rejected because `?trusted=1` would make Nix accept unsigned
  paths from them.
- **Token.** The token is written as `access-tokens` for `github.com` into
  `~/.config/nix/nix.conf` (or under `XDG_CONFIG_HOME`) with mode `0600`, and
  masked in the log. It is not written into `/etc/nix/nix.conf`, which every
  user can read, and not into the environment of later steps. It stays there
  until the job ends, and commands run through `sudo` do not use it. In jobs
  that run untrusted code, grant the job only `contents: read` or set
  `github-token: ""`.
- **Runs.** The action installs Nix once per job on a clean runner. It fails,
  before changing anything, when `/nix`, `/etc/nix`, the group `nixbld`, `nix`
  on `PATH` or the user's `nix.conf` already exists, so it cannot be used twice
  in one job.

## Runner requirements

- GitHub-hosted Linux runners on x86_64 or arm64, such as `ubuntu-24.04` and
  `ubuntu-24.04-arm`. Other runners fail the action before it changes anything:
  macOS, Windows, self-hosted runners and jobs in a container (`container:`),
  which have no systemd.
- The CI of this action runs on Ubuntu 24.04. Other Ubuntu releases give a
  warning, so that `ubuntu-latest` keeps working when GitHub moves it.
- The action uses the runner's `bash`, `curl`, `tar`, `xz`, `sha256sum`, `sudo`
  without password and systemd.

Not supported: binary caches that need credentials on the daemon side, such as
private caches, and `s3://` caches. `/dev/kvm` exists on hosted runners, but the
build users have no access to it, so tests that start virtual machines fail.

## Versioning

The Nix version is part of the public API. A new patch version of Nix is a patch
release of the action and a new minor version a minor release; a Nix release
whose release notes list incompatible changes is a major release. See
[VERSIONING][versioning].

## Bootstrap

This repository is bootstrapped under [FY-0022][fy-0022]. Until their providers
are released:

- actionlint, zizmor, shellcheck, shfmt, Prettier and the other checks of the
  atoms run locally before every pull request (provider: `workflow-check` and
  the atoms);
- pull request titles are checked by the reviewer (provider: `workflow-check`);
- rulesets require no status checks (provider: `workflow-check`);
- OpenSSF Scorecard is not run (provider: `workflow-check`).

## License

[MIT](LICENSE).

[nix]: https://github.com/NixOS/nix
[versioning]: https://github.com/flakeyard/.github/blob/main/VERSIONING.md
[fy-0022]: https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0022-bootstrap.md
