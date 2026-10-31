#!/usr/bin/env bash
# Checks the pinned Nix release: scripts/update/nix.sh with the pinned version
# verifies every tarball and must leave versions.sh unchanged.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
# shellcheck source-path=SCRIPTDIR source=../../versions.sh
source versions.sh
scripts/update/nix.sh "$NIX_VERSION"
git diff --exit-code -- versions.sh
