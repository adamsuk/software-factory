---
repo: adamsuk/viva
issue: 463
issue_repo: adamsuk/software-factory
title: "feat: show confidence against grade on the personal map (adamsuk/software-factory#463)"
branch: factory/463-calibration
base: factory/462-map-disputed
test_command: "npm run typecheck && npm run lint && npm test"
changelog: true
merge_allowed: false
review_bot: none
attempt: 1
created: 2026-11-23
---

## Goal
Add calibration() and a confidence-against-grade table with one sentence.

## Acceptance criteria
See adamsuk/software-factory#463. Built in adamsuk/viva#6.

## Notes
- Built by hand in a Claude Code cloud session acting as the builder station (station containers unavailable there).
- Protected paths: none.
- Stacked: base is the previous ticket's branch; merge in order with merge commits.
