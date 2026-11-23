---
repo: adamsuk/viva
issue: 462
issue_repo: adamsuk/software-factory
title: "feat: leave disputed checks out of the map's gap signals (adamsuk/software-factory#462)"
branch: factory/462-map-disputed
base: factory/459-schema-compat
test_command: "npm run typecheck && npm run lint && npm test"
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-23
---

## Goal
Add a disputed grade kind and leave disputed checks out of thin and confident-wrong.

## Acceptance criteria
See adamsuk/software-factory#462. Built in adamsuk/viva#5.

## Notes
- Built by hand in a Claude Code cloud session acting as the builder station (station containers unavailable there).
- Protected paths: none.
- Stacked: base is the previous ticket's branch; merge in order with merge commits.
