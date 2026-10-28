# shellcheck shell=bash disable=SC2154,SC2034 # shared with tests/lib.sh
# Unit tests of .github/scripts, run as ci/<script> from the copy of the action.

ci_setup() {
  setup
  cp -R "$root/.github/scripts" "$action/scripts/ci"
}

# --- required.sh ------------------------------------------------------------

ci_setup
run "required: all succeeded" ok ci/required.sh \
  NEEDS='{"unit":{"result":"success"},"install":{"result":"success"}}'
finish

ci_setup
run "required: pending may be skipped" ok ci/required.sh \
  NEEDS='{"pending":{"result":"skipped"},"unit":{"result":"success"}}'
finish

for result in failure cancelled skipped; do
  ci_setup
  run "required: a job $result" fail ci/required.sh \
    NEEDS='{"pending":{"result":"success"},"unit":{"result":"'"$result"'"},"install":{"result":"failure"}}'
  expect message "::error::Jobs that did not succeed: unit: $result,install: failure"
  finish
done

# --- commit-status.sh -------------------------------------------------------

ci_setup
run "commit-status: posts the status" ok ci/commit-status.sh GH_TOKEN=t \
  REPO=o/r SHA=abc STATE=success CONTEXT=required RUN_URL=https://x/runs/1
expect call "gh api --silent -X POST repos/o/r/statuses/abc -f state=success -f context=required -f target_url=https://x/runs/1 -f description=GitHub Actions run"
finish

ci_setup
run "commit-status: API failure fails" fail ci/commit-status.sh GH_TOKEN=t \
  REPO=o/r SHA=abc STATE=pending CONTEXT=required RUN_URL=https://x GH_FAILS=1
finish
