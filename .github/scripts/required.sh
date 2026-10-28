#!/usr/bin/env bash
# Fails when any job this job depends on failed or was cancelled.
# Inputs (environment): NEEDS, the needs context as JSON.
set -euo pipefail
failed=$(jq -r 'to_entries[] | select(.value.result == "failure" or .value.result == "cancelled") | .key' <<<"$NEEDS")
if [[ -n $failed ]]; then
  echo "::error::Failed or cancelled jobs: $(paste -sd' ' <<<"$failed")"
  exit 1
fi
