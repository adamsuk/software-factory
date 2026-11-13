---
repo: adamsuk/software-factory
issue: 375
issue_repo: adamsuk/software-factory
title: "fix: run-work-order.sh finds its helpers when run by a relative path (#375)"
branch: factory/375-relative-path-fence
base: main
test_command: "bash scripts/test-run-work-order.sh && bash scripts/test-run-work-order-fence.sh"
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-13
---

## Goal
scripts/run-work-order.sh must find scripts/fence-untrusted.sh when started by a relative path from the repo root. Resolve the script's own directory once at load time, before any cd.

## Acceptance criteria
- [ ] scripts/test-run-work-order.sh loads the script by a relative path, cds away, and asserts fence_issue_text still finds fence-untrusted.sh; it fails on the old behaviour (additions only)
- [ ] scripts/test-run-work-order.sh and scripts/test-run-work-order-fence.sh pass
- [ ] shellcheck scripts/*.sh passes
- [ ] CHANGELOG.md has a dated entry

## Out of scope
- Any other change to the fence, the container launch or the watcher
