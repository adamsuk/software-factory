---
repo: adamsuk/viva-skills
issue: 456
issue_repo: adamsuk/software-factory
title: "feat: onboard viva-skills to the software factory with a skill validator (adamsuk/software-factory#456)"
branch: factory/456-onboard-viva-skills
base: main
test_command: "bash scripts/test-validate-skills.sh && bash scripts/validate-skills.sh"
changelog: true
merge_allowed: false
review_bot: none
attempt: 1
created: 2026-11-23
---

## Goal
Add scripts/validate-skills.sh and its tests, test/changelog/size-label workflows, factory.yml, AGENTS.md, CODEOWNERS, templates and CHANGELOG.md.

## Acceptance criteria
See adamsuk/software-factory#456. Built in adamsuk/viva-skills#1.

## Notes
- Built by hand in a Claude Code cloud session acting as the builder station (station containers unavailable there).
- Protected path (AGENTS.md section 5): goes to the maintainer.
