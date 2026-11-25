---
repo: adamsuk/viva
issue: 497
issue_repo: adamsuk/software-factory
title: "Practice mode: Skills page card, scope practice, experiment 1 says how to run it"
branch: factory/497-practice-platform
base: main
test_command: "npm run typecheck && npm run lint && npm test"
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-25
---

## Goal
Platform half of #497: make practice mode findable and documented in Viva. Merges after adamsuk/viva-skills#24.

## Acceptance criteria
- [ ] The log schema `scope` description lists `practice`, with no field or version change
- [ ] A Skills page card for practice mode, with a test
- [ ] Experiment 1 in the model, and the regenerated EXPERIMENTS.md, say to run it with `/viva practice`
- [ ] `docs/mvp-platform.md` documents the `practice` scope, and the changelog has an entry

## Out of scope
- Log schema field or version changes
