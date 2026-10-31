#!/usr/bin/env bash
# Checks that Nix sends the token of the action to GitHub: with an invalid
# token, fetching a flake from GitHub must fail with HTTP 401.
set -euo pipefail
if output=$(nix flake metadata --no-update-lock-file github:NixOS/nix/2.35.4 2>&1); then
  echo "$output"
  echo "::error::Fetching with an invalid token succeeded: the token is not used."
  exit 1
fi
echo "$output"
if [[ $output != *401* ]]; then
  echo "::error::Fetching failed, but not with HTTP 401."
  exit 1
fi
echo "Nix sent the token of the action to GitHub."
