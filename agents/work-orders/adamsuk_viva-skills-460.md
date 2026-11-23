---
repo: adamsuk/viva-skills
issue: 460
issue_repo: adamsuk/software-factory
title: "feat: viva says what it keeps before the first question (adamsuk/software-factory#460)"
branch: factory/460-say-what-collected
base: factory/457-readme-private
test_command: "bash scripts/test-validate-skills.sh && bash scripts/validate-skills.sh"
changelog: true
merge_allowed: false
review_bot: none
attempt: 1
created: 2026-11-23
---

## Goal
First-run notice in viva; replace IndexedDB wording in both skills.

## Acceptance criteria
See adamsuk/software-factory#460. Built in adamsuk/viva-skills#3.

## Notes
- Built by hand in a Claude Code cloud session acting as the builder station (station containers unavailable there).
- Protected paths: none.
- Stacked: base is the previous ticket's branch; merge in order with merge commits.
