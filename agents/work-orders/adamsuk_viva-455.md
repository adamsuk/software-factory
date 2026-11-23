---
repo: adamsuk/viva
issue: 455
issue_repo: adamsuk/software-factory
title: "feat: onboard Viva to the software factory (adamsuk/software-factory#455)"
branch: factory/455-onboard-viva
base: main
test_command: "npm run typecheck && npm run lint && npm test"
changelog: true
merge_allowed: false
review_bot: none
attempt: 1
created: 2026-11-23
---

## Goal
Add .github/factory.yml, AGENTS.md, CODEOWNERS, the task issue template and a size-label caller pinned by SHA.

## Acceptance criteria
See adamsuk/software-factory#455. Built in adamsuk/viva#2.

## Notes
- Built by hand in a Claude Code cloud session acting as the builder station (station containers unavailable there).
- Protected path (AGENTS.md section 5): goes to the maintainer.
