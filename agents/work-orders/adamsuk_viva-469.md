---
repo: adamsuk/viva
issue: 469
issue_repo: adamsuk/software-factory
title: "ci: pin pages.yml actions by SHA, narrow its token, test every PR (adamsuk/software-factory#469)"
branch: factory/469-pin-pages
base: main
test_command: "npm run typecheck && npm run lint && npm test"
changelog: true
merge_allowed: false
review_bot: none
attempt: 1
created: 2026-11-23
---

## Goal
Pin pages.yml actions by SHA, scope pages/id-token to deploy, run test.yml on every PR.

## Acceptance criteria
See adamsuk/software-factory#469. Built in adamsuk/viva#10.

## Notes
- Built by hand in a Claude Code cloud session acting as the builder station (station containers unavailable there).
- Protected path (AGENTS.md section 5): goes to the maintainer.
