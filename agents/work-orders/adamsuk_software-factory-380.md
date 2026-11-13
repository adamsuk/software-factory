---
repo: adamsuk/software-factory
issue: 380
issue_repo: adamsuk/software-factory
title: "test: replay adversarial issue text through the fence (#380)"
branch: factory/380-adversarial-fence-tests
base: main
test_command: "bash scripts/test-untrusted-issue.sh && bash scripts/test-watcher-fence.sh"
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-13
---

## Goal
Add recorded adversarial issue-text fixtures and extend the two existing fence tests to replay them through the station bundle and the watcher prompt, proving hostile text stays inside the fence. Regression guard only.

## Acceptance criteria
- [ ] Fixtures under scripts/fixtures (fake closers, instruction lines, zero-width characters)
- [ ] scripts/test-untrusted-issue.sh exits zero and fails without the guard
- [ ] scripts/test-watcher-fence.sh exits zero with a hostile-fence-closer case
- [ ] the tests job in lint.yml exits zero

## Out of scope
- Changing fence-untrusted.sh, the watcher or station-run.sh
