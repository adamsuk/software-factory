---
repo: adamsuk/viva
issue: 458
issue_repo: adamsuk/software-factory
title: "feat: keep the personal map's log in this browser (adamsuk/software-factory#458)"
branch: factory/458-map-persist
base: factory/455-onboard-viva
test_command: "npm run typecheck && npm run lint && npm test"
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-23
---

## Goal
Persist the personal map's lines in localStorage with add/replace, download and forget, and say what is kept.

## Acceptance criteria
See adamsuk/software-factory#458. Built in adamsuk/viva#3.

## Notes
- Built by hand in a Claude Code cloud session acting as the builder station (station containers unavailable there).
- Protected paths: none.
- Stacked: base is the previous ticket's branch; merge in order with merge commits.
