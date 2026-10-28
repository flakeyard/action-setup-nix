# shellcheck shell=bash disable=SC2034
# The Nix release this action installs. Update with scripts/update-nix.sh,
# never by hand: the hashes are checked against cache.nixos.org there.
NIX_VERSION=2.35.4
NIX_BASE_URL=https://releases.nixos.org/nix
NIX_SHA256_x86_64_linux=ff66236d2f7e2a21f3350e73668e021ac6a8881ef277a38e16e952bfb22718c3
NIX_SHA256_aarch64_linux=14a940a2d0ae5b2c623dc2ca168311c9367fd4bc416f6ded0c1087089d6de934

# Ubuntu releases that the CI of this action runs on.
TESTED_UBUNTU=(24.04)
