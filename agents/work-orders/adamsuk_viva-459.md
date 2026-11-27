---
repo: adamsuk/viva
issue: 459
issue_repo: adamsuk/software-factory
title: "feat: match log schemas by skill version range and count skipped lines (adamsuk/software-factory#459)"
branch: factory/459-schema-compat
base: factory/458-map-persist
test_command: "npm run typecheck && npm run lint && npm test"
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-23
---

## Goal
Match schemas by skillVersions range, count skipped and unknown-version lines, group topics case-insensitively.

## Acceptance criteria
See adamsuk/software-factory#459. Built in adamsuk/viva#4.

## Notes
- Built by hand in a Claude Code cloud session acting as the builder station (station containers unavailable there).
- Protected paths: none.
- Stacked: base is the previous ticket's branch; merge in order with merge commits.
