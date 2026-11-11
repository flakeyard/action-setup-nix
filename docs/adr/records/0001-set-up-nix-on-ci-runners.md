---
id: ADR-0001
title: Set up Nix on CI runners
status: accepted
date: 2026-11-05
supersedes: []
superseded_by: []
related: []
affects:
  [
    "action.yml",
    "versions.sh",
    "scripts/**",
    "tests/**",
    ".github/workflows/test.yaml",
    "README.md",
  ]
review_by:
---

## Context

This record moves [FY-0023][fy-0023] from [flakeyard/decisions][decisions]
unchanged in substance. Records there that also govern this repository include
[FY-0024][fy-0024] (versioning and support) and [FY-0036][fy-0036] (the order of
Nix minor updates of this action and the image).

CI runs on GitHub-hosted runners with Nix installed by `action-setup-nix`, in
multi-user mode, with the sandbox on and no fallback ([FY-0009][fy-0009]). It is
the only action that runs before Nix exists, so it cannot take its tools from a
`flake.lock` and pins its installer by hash instead ([FY-0030][fy-0030]). Every
check of flakeyard and of its consumers runs under the configuration it writes.

The configuration in `/etc/nix/nix.conf` is read by the Nix daemon, which builds
and substitutes for every user of the runner:

- A substituter listed there is used for every build, and a path it serves is
  accepted when it is signed by any trusted key.
- The URL of a binary cache store accepts parameters, and `?trusted=1` makes Nix
  accept its paths without signatures. `#` starts a comment, and a newline
  starts a new setting.
- A user that is not in `trusted-users` cannot add substituters or keys through
  flake `nixConfig`, `--option` or their own `nix.conf`; the daemon ignores
  them. Settings that only affect the client, such as `access-tokens` or
  `accept-flake-config`, are still read from the user's own `nix.conf`.

Fetching flake inputs from GitHub happens in the client. Without a token, it is
limited to 60 API requests per hour per address, and hosted runners share
addresses.

Reading the official installer of Nix 2.35 showed:

- the release tarball of each system contains an `install` script that sets up
  the daemon, build users and systemd units and writes a given file into
  `nix.conf`;
- in daemon mode it edits `/etc/bashrc`, `/etc/profile.d/nix.sh`, `/etc/zshrc`,
  `/etc/bash.bashrc` and `/etc/zsh/zshrc` even when asked not to modify
  profiles;
- without systemd it only prints a warning and finishes without a running
  daemon;
- it takes settings from environment variables such as `NIX_USER_COUNT`,
  `NIX_BUILD_GROUP_ID` and `NIX_SSL_CERT_FILE`, which an earlier step of a job
  can set for all later steps.

## Decision

### Installation

`action-setup-nix` installs Nix from the official release tarball of NixOS/nix
for the runner's system. The version, the download URL and the SHA-256 of every
tarball are fixed in this repository; nothing at run time, including inputs and
environment variables, can change them. The tarball is verified before it is
unpacked, and its installer runs in daemon mode with an environment that
contains only what it needs.

The action supports GitHub-hosted Linux runners with systemd, on x86_64 and
arm64. Before it changes anything, it checks that the runner is such a runner
and that Nix was not installed on it before: no `/nix`, no `/etc/nix`, no
`nixbld` group, no `nix` on `PATH` and no user `nix.conf`. Otherwise it fails.
An Ubuntu release that the action's CI does not test gives a warning, not a
failure, so that consumers on `ubuntu-latest` keep working when GitHub moves it.

### Nix version

The action installs Nix from NixOS/nix, the implementation of the dev container
image, with the same minor version as the image ([FY-0009][fy-0009]). Each
release of the action fixes one Nix version. A new Nix version is taken only
with the hashes of its tarballs checked against the signed narinfo of the same
store paths in `cache.nixos.org`, where those exist.

### Configuration

The action writes this configuration, and nothing else, into
`/etc/nix/nix.conf`, in addition to what the installer writes itself:

- `sandbox = true` and `sandbox-fallback = false`;
- `substituters` and `trusted-public-keys` with only `cache.nixos.org`;
- `require-sigs = true` and `accept-flake-config = false`;
- `extra-experimental-features = nix-command flakes`;
- `max-jobs = auto`, `connect-timeout = 10` and `fallback = true`.

`trusted-users` keeps its default, `root`. On a hosted runner the job can still
change everything through `sudo`, so this is not a boundary against the job. It
prevents trust from widening by accident: flake `nixConfig`, `--option` and
tools that write the user's `nix.conf` cannot add caches. The inputs of the
action are the only supported way to add them:

- `extra-substituters`: URLs with the scheme `https`, without user information,
  query, fragment or whitespace;
- `extra-trusted-public-keys`: Ed25519 keys of the form `<name>:<base64>`.

Keys without substituters are an error. Substituters without keys are allowed,
because a mirror of `cache.nixos.org` is signed by its key, and give a notice.
The action has no input for free-form configuration.

### Token

The input `github-token` defaults to `GITHUB_TOKEN`; an empty value disables it.
The token must consist only of letters, digits, underscores, dots and hyphens.
It is written as `access-tokens` for `github.com` into the `nix.conf` of the
runner's user, with mode `0600`, and is masked in the log. It is not written
into `/etc/nix/nix.conf`, which every user can read, and not into the
environment of later steps. It stays on disk until the job ends; commands run
through `sudo` do not use it.

### Public API

The public API of `action-setup-nix`, in addition to what [FY-0024][fy-0024]
lists for every action, is:

- the Nix implementation and its version policy;
- the configuration above and the validation rules of its inputs;
- the behaviour on a runner where Nix was installed before;
- the effects that later steps can rely on: `nix` on `PATH`, a running daemon,
  the edited shell profiles and the build users and group of the installer.

The action's CI runs on every supported runner and weekly on a schedule, because
an update of the runner images can break the action without a release.

## Constraints

### Installer and runners

- The action MUST install Nix only from the official release tarball of
  NixOS/nix, and MUST verify its SHA-256, fixed in the repository, before
  unpacking it.
- The version, URLs and hashes MUST NOT be changeable by inputs or environment
  variables.
- The installer MUST run in daemon mode with an environment reduced to what it
  needs.
- The action MUST fail, before changing the runner, on runners other than
  GitHub-hosted Linux runners with systemd on x86_64 or arm64, and on runners
  where Nix was installed before.
- The action's CI MUST run on every supported runner and on a weekly schedule.

### Nix

- The action MUST install the Nix implementation and minor version of the dev
  container image.
- A Nix update MUST check the tarball hashes against the signed narinfo in
  `cache.nixos.org` when the store paths are there.

### Trust

- `/etc/nix/nix.conf` MUST contain the settings of this decision and nothing
  else besides what the installer writes.
- `trusted-users` MUST stay `root`.
- Extra substituters MUST be `https` URLs without user information, query,
  fragment or whitespace. Extra keys MUST be Ed25519 public keys. Keys without
  substituters MUST fail the action.
- The action MUST NOT offer free-form configuration.

### Token storage

- A token MUST be validated before use, MUST be stored only in the runner user's
  `nix.conf` with mode `0600` and MUST be masked.
- A token MUST NOT be written into `/etc/nix/nix.conf` or into the environment
  of later steps.

### Documentation

- The Nix implementation and version policy, the configuration, the input rules,
  the behaviour on runners with Nix and the effects listed in this decision MUST
  be documented as public API.

## Consequences

- (+) Every CI job of flakeyard and of its consumers runs the same Nix with the
  same trusted caches, and only the inputs of the action can add caches.
- (+) A tarball that differs from the reviewed one, a malformed input or an
  unsupported runner fails before anything is installed.
- (+) The checks of runner image updates do not wait for a release.
- (−) Running the action twice in one job, or on a runner with Nix, fails; jobs
  that already have Nix do not use the action.
- (−) Private caches that need credentials on the daemon side and `s3://` caches
  are not supported.
- (−) The upstream installer edits shell profiles; login shells of later steps
  load Nix's environment.
- (±) A Nix update needs a maintainer to fetch and review hashes; Renovate can
  only report that a new version exists.

## Alternatives considered

- **`cachix/install-nix-action` or the Determinate installer.** Maintained
  elsewhere and widely used, but each release changes the installed Nix or the
  configuration on its own schedule, and the Determinate installer installs a
  different distribution of Nix than the image.
- **Own installation without the upstream installer.** Would avoid the profile
  edits, but would reimplement build users, systemd units and store
  registration, and would miss fixes of the installer.
- **Free-form configuration input.** Flexible, but any setting, including
  `trusted-users` and `?trusted=1`, would reach the daemon.
- **A no-op on a second run with the same inputs.** Friendlier, but it requires
  comparing the installed state, and can be added later without breaking anyone;
  the reverse change would be breaking.
- **The token in `NIX_CONFIG` through the job environment.** Simpler, but it
  would reach every later step and every action they call.

[decisions]: https://github.com/flakeyard/decisions
[fy-0009]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0009-ci-on-runners.md
[fy-0023]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0023-setup-nix.md
[fy-0024]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0024-versioning-and-support.md
[fy-0030]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0030-actions-workflows-and-release-bot.md
[fy-0036]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0036-check-the-end-of-life-of-nixpkgs-in-flake-lock.md
