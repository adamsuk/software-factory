---
repo: adamsuk/viva-skills
issue: 461
issue_repo: adamsuk/software-factory
title: "feat: viva lets you dispute a bad question (adamsuk/software-factory#461)"
branch: factory/461-dispute
base: factory/460-say-what-collected
test_command: "bash scripts/test-validate-skills.sh && bash scripts/validate-skills.sh"
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-23
---

## Goal
Dispute step in viva; viva-assess leaves disputed checks out of its signals.

## Acceptance criteria
See adamsuk/software-factory#461. Built in adamsuk/viva-skills#4.

## Notes
- Built by hand in a Claude Code cloud session acting as the builder station (station containers unavailable there).
- Protected paths: none.
- Stacked: base is the previous ticket's branch; merge in order with merge commits.
