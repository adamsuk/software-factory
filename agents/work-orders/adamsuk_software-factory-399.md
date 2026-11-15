---
repo: adamsuk/software-factory
issue: 399
issue_repo: adamsuk/software-factory
title: "feat: move the watcher's review and dependabot-triage call sites onto the provider seam (#399)"
branch: factory/399-watcher-provider-review-dependabot
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-watcher-provider.sh && bash scripts/test-ir-verdict-parse.sh && bash scripts/test-watcher-fence.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 2
created: 2026-11-15
---

## Goal
Route the `review` and `dependabot-triage` kinds in `run_grok` through the
provider seam from #398, expressing the schema provider-neutrally. Piece 2 of 4
of #397.

## Acceptance criteria
- [ ] `scripts/test-watcher-provider.sh` has new cases for both kinds on a non-grok provider.
- [ ] `scripts/test-ir-verdict-parse.sh` and `scripts/test-watcher-fence.sh` exit zero.
- [ ] Unset or `grok` provider still passes `--json-schema`.
- [ ] No existing assertion changed. CHANGELOG entry added.

## Out of scope
Other `run_grok` kinds, pieces 3 and 4, adapter changes.
