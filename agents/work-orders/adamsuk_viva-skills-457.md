---
repo: adamsuk/viva-skills
issue: 457
issue_repo: adamsuk/software-factory
title: "docs: README says logs stay on your device, not in a gist (adamsuk/software-factory#457)"
branch: factory/457-readme-private
base: factory/456-onboard-viva-skills
test_command: "bash scripts/test-validate-skills.sh && bash scripts/validate-skills.sh"
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-23
---

## Goal
Rewrite the README's logging text to match the skills and add a What is stored section.

## Acceptance criteria
See adamsuk/software-factory#457. Built in adamsuk/viva-skills#2.

## Notes
- Built by hand in a Claude Code cloud session acting as the builder station (station containers unavailable there).
- Protected paths: none.
- Stacked: base is the previous ticket's branch; merge in order with merge commits.
