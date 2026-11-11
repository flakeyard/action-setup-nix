# Changelog

## [0.1.4](https://github.com/flakeyard/action-setup-nix/compare/v0.1.3...v0.1.4) (2026-11-11)


### Bug Fixes

* **deps:** update flakeyard/action-shell-lib action to v0.1.2 ([#68](https://github.com/flakeyard/action-setup-nix/issues/68)) ([66f30a0](https://github.com/flakeyard/action-setup-nix/commit/66f30a04327c176619255a5acaf9212f8d90d599))
* **deps:** update flakeyard/action-shell-lib action to v0.1.3 ([#70](https://github.com/flakeyard/action-setup-nix/issues/70)) ([20f71fb](https://github.com/flakeyard/action-setup-nix/commit/20f71fb534df5d913d06b402577d6e79574cdb6d))

## [0.1.3](https://github.com/flakeyard/action-setup-nix/compare/v0.1.2...v0.1.3) (2026-11-10)


### Bug Fixes

* run the steps through action-shell-lib ([#59](https://github.com/flakeyard/action-setup-nix/issues/59)) ([95e61a7](https://github.com/flakeyard/action-setup-nix/commit/95e61a73dc4d541a2f7cf6df190f64872ae4e7ea))

## [0.1.2](https://github.com/flakeyard/action-setup-nix/compare/v0.1.1...v0.1.2) (2026-11-05)


### Bug Fixes

* follow redirects only to https ([#39](https://github.com/flakeyard/action-setup-nix/issues/39)) ([3a1dfb0](https://github.com/flakeyard/action-setup-nix/commit/3a1dfb08577c85312dbca72512045b09fe34b7c3))
* read narinfo and .reginfo like Nix does ([#40](https://github.com/flakeyard/action-setup-nix/issues/40)) ([82ad283](https://github.com/flakeyard/action-setup-nix/commit/82ad2837b6ea58d59a728aa62a870d039d123df4))
* run no tool of the job PATH before lib/env.sh replaces it ([#36](https://github.com/flakeyard/action-setup-nix/issues/36)) ([4dfac22](https://github.com/flakeyard/action-setup-nix/commit/4dfac22818a0a61e97c7d78998b19f8a88303da0))

## [0.1.1](https://github.com/flakeyard/action-setup-nix/compare/v0.1.0...v0.1.1) (2026-10-31)


### Bug Fixes

* gaps in the tarball checks ([#20](https://github.com/flakeyard/action-setup-nix/issues/20)) ([27553d4](https://github.com/flakeyard/action-setup-nix/commit/27553d493e3fb4138fdf73fe02b7a8804231d131))
* run the scripts without functions, shell options and variables of the job ([#19](https://github.com/flakeyard/action-setup-nix/issues/19)) ([4e095ce](https://github.com/flakeyard/action-setup-nix/commit/4e095cea174450f3a34e521b433b519899c2d909))

## 0.1.0 (2026-10-28)


### Features

* check Nix tarballs against cache.nixos.org ([#7](https://github.com/flakeyard/action-setup-nix/issues/7)) ([ed0af59](https://github.com/flakeyard/action-setup-nix/commit/ed0af5938a84596364113a249abbb83c06b07856))
* check the runner and inputs before installing ([#3](https://github.com/flakeyard/action-setup-nix/issues/3)) ([a88573d](https://github.com/flakeyard/action-setup-nix/commit/a88573d3bc5c53a967de083c8c11b32e696f9fcf))
* install the pinned Nix with the configuration of FY-0023 ([#4](https://github.com/flakeyard/action-setup-nix/issues/4)) ([6dddfb8](https://github.com/flakeyard/action-setup-nix/commit/6dddfb85434e7f06a92a5d2a194977070ee9cb2d))
* pin new Nix releases with update-nix.sh ([#8](https://github.com/flakeyard/action-setup-nix/issues/8)) ([c0f9aab](https://github.com/flakeyard/action-setup-nix/commit/c0f9aabfa85614237c194e898d591cde142a1f33))
* verify the installation and wire the action ([#5](https://github.com/flakeyard/action-setup-nix/issues/5)) ([cb17e5e](https://github.com/flakeyard/action-setup-nix/commit/cb17e5e28a996d9426842c9b78be4af519d123bc))


### Bug Fixes

* name the unsupported runner on macOS and Windows ([#17](https://github.com/flakeyard/action-setup-nix/issues/17)) ([8110d10](https://github.com/flakeyard/action-setup-nix/commit/8110d10f6cdbac475c5f7a182060bb904068e8fd))
