#!/usr/bin/env bash
# Checks that the action failed before changing the runner.
# Inputs (environment): OUTCOME, the outcome of the action's step.
set -euo pipefail
if [[ $OUTCOME != failure ]]; then
  echo "::error::The action did not fail (outcome: $OUTCOME)."
  exit 1
fi
for path in /nix /etc/nix "$HOME/.config/nix/nix.conf"; do
  if [[ -e $path ]]; then
    echo "::error::The action failed, but created $path."
    exit 1
  fi
done
echo "The action failed without changing the runner."
