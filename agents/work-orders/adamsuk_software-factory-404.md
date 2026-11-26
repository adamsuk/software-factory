---
repo: adamsuk/software-factory
issue: 404
issue_repo: adamsuk/software-factory
title: "feat: route the watcher plan call site through the provider seam (#404)"
branch: factory/404-plan-provider-seam
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-watcher-provider.sh && bash scripts/test-watcher-env.sh && bash scripts/test-watcher-fence.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-26
---

## Goal
Route the watcher's `plan` call site (`scripts/watcher/watch.sh` and
`watch.new.sh`) through the provider seam from #398, with the same sandbox and
deny rules for every provider. State in the PR body where the adapter is found
when the working directory is not the home-repo clone, and which role (not
`intake`) a write-access call site passes. Piece 1 of 4 of #400.

## Acceptance criteria
- [ ] `scripts/test-watcher-provider.sh` has a new case showing the plan call site invokes a non-grok provider with no grok on PATH; it fails without the change.
- [ ] A new case shows the grok command line for the plan call site is unchanged when `FACTORY_PROVIDER` is unset or `grok`.
- [ ] `scripts/test-watcher-env.sh` and `scripts/test-watcher-fence.sh` exit zero.
- [ ] The `tests` job in `.github/workflows/lint.yml` exits zero.
- [ ] PR body names the adapter-location and role decisions, and the watcher test commands run by hand.
- [ ] No existing assertion changed. CHANGELOG entry added.

## Out of scope
The other three pieces of #400, the triage call site, changing any existing
watcher test assertion (AGENTS.md section 5).
