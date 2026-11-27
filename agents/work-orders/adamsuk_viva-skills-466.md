---
repo: adamsuk/viva-skills
issue: 466
issue_repo: adamsuk/software-factory
title: "feat: viva checks a bot review comment before you forward it (adamsuk/software-factory#466)"
branch: factory/466-review-comment
base: factory/465-ai-use
test_command: "bash scripts/test-validate-skills.sh && bash scripts/validate-skills.sh"
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-23
---

## Goal
Add a review-comment scope to viva.

## Acceptance criteria
See adamsuk/software-factory#466. Built in adamsuk/viva-skills#6.

## Notes
- Built by hand in a Claude Code cloud session acting as the builder station (station containers unavailable there).
- Protected paths: none.
- Stacked: base is the previous ticket's branch; merge in order with merge commits.
