---
repo: adamsuk/software-factory
issue: 389
issue_repo: adamsuk/software-factory
title: "feat: provider-neutral budget and ledger field names (#389)"
branch: factory/389-neutral-budget-names
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-adapters.sh && bash scripts/test-check-test-assertions.sh && bash scripts/test-factory-flagged.sh && bash scripts/test-run-work-order.sh && bash scripts/test-run-work-order-llm.sh && bash scripts/test-station-run.sh && bash scripts/test-wait-for-review-bot.sh && bash scripts/test-research-brief.sh"
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-25
---

## Goal
Add provider-neutral budget names (max_build_runs_per_week/day) and a `sessions` ledger column, reading the old grok-named fields as fallbacks.

## Acceptance criteria
See adamsuk/software-factory#389. Built in adamsuk/software-factory#499.

## Notes
- Work order reconstructed after the builder run did not commit it.
- Protected paths: none.
