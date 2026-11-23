---
repo: adamsuk/viva
issue: 464
issue_repo: adamsuk/software-factory
title: "feat: log schema 0.4 records how the change was made (adamsuk/software-factory#464)"
branch: factory/464-ai-use
base: factory/463-calibration
test_command: "npm run typecheck && npm run lint && npm test"
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-23
---

## Goal
Add log schema 0.4.0 with ai-use, byAiUse() and a table on the map.

## Acceptance criteria
See adamsuk/software-factory#464. Built in adamsuk/viva#7.

## Notes
- Built by hand in a Claude Code cloud session acting as the builder station (station containers unavailable there).
- Protected paths: none.
- Stacked: base is the previous ticket's branch; merge in order with merge commits.
