#!/usr/bin/env bash
# TEMPORARY. Named aaa so the glob runs it FIRST: a canary that sorts last
# cannot show that later suites still run after one fails. Proves two things about the `tests` job added by #135 that nothing
# had ever tested, then is removed in the next commit of the same pull request:
#
#   1. the job's glob picks up a suite that did not exist when the job was
#      written, and
#   2. a failing suite actually fails the job and blocks the merge.
#
# Both were asserted and never observed: every run of the job so far has passed,
# so the branch that reports failure had never executed. See #135.
set -euo pipefail
echo "canary: deliberately failing to prove the tests job catches a red suite"
exit 1
