---
repo: adamsuk/software-factory
issue: 387
issue_repo: adamsuk/software-factory
title: "feat: read and validate FACTORY_PROVIDER in the watcher env block (#387)"
branch: factory/387-watcher-provider-env
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-adapters.sh && bash scripts/test-station-run.sh && bash scripts/test-watcher-env.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-13
---

## Goal
Narrowed by the maintainer (option 1, 2026-11-13): read and validate
`FACTORY_PROVIDER` (`grok`, `claudecode` or `opencode`; default `grok`) in the
factory env block shared by the watcher scripts. An invalid value stops the
watcher with a clear message. The value is not used yet; `run_grok` and
`station-run.sh` call sites are untouched.

## Acceptance criteria
- [ ] `scripts/test-watcher-env.sh` has new cases: each of the three providers, unset defaults to `grok`, an invalid value is rejected. They fail without the change; no existing assertion changes.
- [ ] `scripts/test-station-run.sh` and `scripts/test-adapters.sh` exit zero.
- [ ] `scripts/watcher/README.md` documents `FACTORY_PROVIDER`.
- [ ] `CHANGELOG.md` dated entry.

## Likely files
- `scripts/watcher/*.sh` (env block, identical in all)
- `scripts/test-watcher-env.sh`, `scripts/watcher/README.md`, `CHANGELOG.md`

## Out of scope
- Routing agent calls through a provider, `run_grok`, #388, #390, #391.

## Issue text (untrusted)
> Read FACTORY_PROVIDER in the factory env block, validate it, default grok. (Premise that the watcher calls station-run.sh withdrawn by the maintainer.)
