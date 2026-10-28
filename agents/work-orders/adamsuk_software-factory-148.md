---
repo: adamsuk/software-factory
issue: 148
issue_repo: adamsuk/software-factory
title: "fix: close the four CodeRabbit findings from PR #143"
branch: factory/148-coderabbit-findings
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-10-28
---

## Goal

`main` carries #142's write boundary with four known holes, because the
independent verdicts were posted before CodeRabbit finished and the fixes were
pushed after the merge. Close them.

## Acceptance criteria

- [ ] `scripts/station-run.sh reviewer /dev/null` sandboxes with no flag
- [ ] `--writable` is required to run a non-builder role in the real repository
- [ ] An exported `GIT_DIR` cannot make the station touch that repository
- [ ] A failed `git diff` fails `check-test-assertions.sh`
- [ ] A failure between clone and launch leaves no `/tmp/station-ro-*`
- [ ] `stations/README.md` says the original checkout stays reachable by
      absolute path, and names #44
- [ ] `scripts/test-station-run.sh` covers the default, `--writable` and the
      `GIT_DIR` case, and does not damage the checkout when it runs

## Likely files

- scripts/station-run.sh
- scripts/check-test-assertions.sh
- scripts/test-station-run.sh
- stations/README.md

## Out of scope

- Real OS isolation (#44), scoped credentials (#7)
- Waiting for the review bot so this cannot recur (#147)

## Issue text (untrusted)

> Close the four CodeRabbit findings that merged around in #142
