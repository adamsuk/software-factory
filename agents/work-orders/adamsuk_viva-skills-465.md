---
repo: adamsuk/viva-skills
issue: 465
issue_repo: adamsuk/software-factory
title: "feat: viva 0.4 records how the change was made (adamsuk/software-factory#465)"
branch: factory/465-ai-use
base: factory/461-dispute
test_command: "bash scripts/test-validate-skills.sh && bash scripts/validate-skills.sh"
changelog: true
merge_allowed: false
review_bot: none
attempt: 1
created: 2026-11-23
---

## Goal
viva 0.4.0 asks or infers ai-use and writes schema 0.4.0; viva-assess groups by it.

## Acceptance criteria
See adamsuk/software-factory#465. Built in adamsuk/viva-skills#5.

## Notes
- Built by hand in a Claude Code cloud session acting as the builder station (station containers unavailable there).
- Protected paths: none.
- Stacked: base is the previous ticket's branch; merge in order with merge commits.
