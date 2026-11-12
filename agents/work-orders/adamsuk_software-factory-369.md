---
repo: adamsuk/software-factory
issue: 369
issue_repo: adamsuk/software-factory
title: "feat: block egress in software-factory workflows (Harden-Runner)"
branch: factory/369-softwarefactory-egress-block
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-adapters.sh && bash scripts/test-check-test-assertions.sh && bash scripts/test-factory-flagged.sh && bash scripts/test-run-work-order.sh && bash scripts/test-run-work-order-llm.sh && bash scripts/test-station-run.sh && bash scripts/test-wait-for-review-bot.sh && bash scripts/test-research-brief.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-12
---

## Goal
Set Harden-Runner `egress-policy: block` with exact-host allowlists (from the
maintainer-supplied audited runs) on lint.yml shellcheck and tests, and
metrics.yml metrics. test-assertions, ruleset-drift and line-audit stay on
audit with a comment saying why (no recommended-host list supplied yet).

## Acceptance criteria
- [ ] Block jobs use only the hosts from the cited runs, no wildcards.
- [ ] Audit jobs carry a comment naming why.
- [ ] scripts/test-harden-runner.sh fails if a blocking job goes back to audit.
- [ ] CHANGELOG.md has a dated entry.

## Protected change (needs maintainer review)
Touches .github/workflows/**. scripts/test-harden-runner.sh previously asserted
every step was audit; that assertion is replaced by a stricter per-job
audit|block check (needs approved-test-change).
