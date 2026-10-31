# shellcheck shell=bash disable=SC2154,SC2034 # shared with tests/harness
# Unit tests of .github/scripts/required.sh.

github_setup
run "required: all succeeded" ok github/required.sh \
  NEEDS='{"unit":{"result":"success"},"install":{"result":"success"}}'
finish

github_setup
run "required: pending may be skipped" ok github/required.sh \
  NEEDS='{"pending":{"result":"skipped"},"unit":{"result":"success"}}'
finish

for result in failure cancelled skipped; do
  github_setup
  run "required: a job $result" fail github/required.sh \
    NEEDS='{"pending":{"result":"success"},"unit":{"result":"'"$result"'"},"install":{"result":"failure"}}'
  expect message "::error::Jobs that did not succeed: unit: $result,install: failure"
  finish
done
