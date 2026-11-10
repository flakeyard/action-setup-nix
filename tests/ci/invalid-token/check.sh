#!/usr/bin/env bash
# Checks that Nix sends the token of the action to GitHub: with an invalid
# token, fetching a flake from GitHub must fail with HTTP 401.
# Inputs (environment): SHELL_LIB.
set -euo pipefail
# shellcheck source=/dev/null # the library, from SHELL_LIB
source "$SHELL_LIB/report.sh"
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.."
# shellcheck source-path=SCRIPTDIR source=../../../versions.sh
source versions.sh
if output=$(nix flake metadata --no-update-lock-file "github:NixOS/nix/$NIX_VERSION" 2>&1); then
  echo "$output"
  fail "Fetching with an invalid token succeeded: the token is not used."
fi
echo "$output"
[[ $output == *401* ]] || fail "Fetching failed, but not with HTTP 401."
echo "Nix sent the token of the action to GitHub."
