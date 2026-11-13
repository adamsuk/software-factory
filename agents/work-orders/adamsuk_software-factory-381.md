---
repo: adamsuk/software-factory
issue: 381
issue_repo: adamsuk/software-factory
title: "feat: record rework rounds from PR data in the delivery metrics (#381)"
branch: factory/381-rework-recovery-metrics
base: main
test_command: "bash scripts/test-factory-delivery-metrics.sh"
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-13
---

## Goal
Make the weekly delivery metrics report numeric rework rounds per PR and recovery time (hours) instead of `n/a`, computed from PR and run data.

## Acceptance criteria
- [ ] scripts/factory-delivery-metrics.sh prints a numeric rework rounds per PR and recovery time hours on a fixture that contains a fix round
- [ ] scripts/test-factory-delivery-metrics.sh exits zero, with a new case that fails without the change
- [ ] the metrics job in .github/workflows/metrics.yml exits zero (the workflow itself is not edited)

## Out of scope
- Cost per change (needs the factory host ledger) and the pre-agent baseline
- Editing .github/workflows/metrics.yml (protected; flagged for the maintainer)
