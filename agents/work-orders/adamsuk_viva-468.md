---
repo: adamsuk/viva
issue: 468
issue_repo: adamsuk/software-factory
title: "feat: suggest re-checking a missed topic after a week (adamsuk/software-factory#468)"
branch: factory/468-recheck
base: factory/467-next-steps
test_command: "npm run typecheck && npm run lint && npm test"
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-23
---

## Goal
Mark topics whose latest counted check was partial or missed seven or more days ago.

## Acceptance criteria
See adamsuk/software-factory#468. Built in adamsuk/viva#9.

## Notes
- Built by hand in a Claude Code cloud session acting as the builder station (station containers unavailable there).
- Protected paths: none.
- Stacked: base is the previous ticket's branch; merge in order with merge commits.
