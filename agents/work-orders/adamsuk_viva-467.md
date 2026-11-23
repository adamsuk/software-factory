---
repo: adamsuk/viva
issue: 467
issue_repo: adamsuk/software-factory
title: "feat: tie the map's next steps to the guide's recommendations (adamsuk/software-factory#467)"
branch: factory/467-next-steps
base: factory/464-ai-use
test_command: "npm run typecheck && npm run lint && npm test"
changelog: true
merge_allowed: false
review_bot: none
attempt: 1
created: 2026-11-23
---

## Goal
Key next steps to recommendation ids and show one habit when nothing is thin.

## Acceptance criteria
See adamsuk/software-factory#467. Built in adamsuk/viva#8.

## Notes
- Built by hand in a Claude Code cloud session acting as the builder station (station containers unavailable there).
- Protected paths: none.
- Stacked: base is the previous ticket's branch; merge in order with merge commits.
