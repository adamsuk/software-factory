---
repo: adamsuk/software-factory
issue: 454
issue_repo: adamsuk/software-factory
title: "feat: enrol adamsuk/viva and adamsuk/viva-skills in the default repo list (#454)"
branch: factory/454-enrol-viva
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-adapters.sh && bash scripts/test-check-test-assertions.sh && bash scripts/test-factory-flagged.sh && bash scripts/test-run-work-order.sh && bash scripts/test-run-work-order-llm.sh && bash scripts/test-station-run.sh && bash scripts/test-wait-for-review-bot.sh && bash scripts/test-research-brief.sh"
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-23
---

## Goal
Add both viva repos to DEFAULT_REPOS in scripts/triage-ask.sh and scripts/triage-apply-answers.sh, with added test cases and a README row.

## Acceptance criteria
See adamsuk/software-factory#454. Built in adamsuk/software-factory#470.

## Notes
- Built by hand in a Claude Code cloud session acting as the builder station (station containers unavailable there).
- Protected paths: none.
