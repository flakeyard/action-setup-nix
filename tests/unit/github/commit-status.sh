# shellcheck shell=bash disable=SC2154,SC2034 # shared with tests/harness
# Unit tests of .github/scripts/commit-status.sh.

github_setup
run "commit-status: posts the status" ok github/commit-status.sh GH_TOKEN=t \
  REPO=o/r SHA=abc STATE=success CONTEXT=required RUN_URL=https://x/runs/1
expect call "gh api --silent -X POST repos/o/r/statuses/abc -f state=success -f context=required -f target_url=https://x/runs/1 -f description=GitHub Actions run"
finish

github_setup
run "commit-status: API failure fails" fail github/commit-status.sh GH_TOKEN=t \
  REPO=o/r SHA=abc STATE=pending CONTEXT=required RUN_URL=https://x GH_FAILS=1
finish
