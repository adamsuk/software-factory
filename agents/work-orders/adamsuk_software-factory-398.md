---
repo: adamsuk/software-factory
issue: 398
issue_repo: adamsuk/software-factory
title: "feat: add a provider seam to the watcher's run_grok, triage first (#398)"
branch: factory/398-watcher-provider-seam
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-watcher-provider.sh && bash scripts/test-watcher-env.sh && bash scripts/test-watcher-fence.sh && bash scripts/test-adapters.sh && bash scripts/test-station-run.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 2
created: 2026-11-13
---

Reconstructed on 2026-11-13 from the triage comment on #398 and pull request
#403: the foreman run opened the pull request without committing this file.
`attempt: 2` records one fix round (ShellCheck SC2015 in the new test).

## Goal
Give `run_grok` in `scripts/watcher/watch.sh` (and `watch.new.sh`) a provider
seam selected by `FACTORY_PROVIDER`, through the adapters under `adapters/`,
and move the issue-triage call site onto it. Other call sites keep calling
grok. Piece 1 of 4 (part of #397, parent #386). #387 is merged.

## Acceptance criteria
- [ ] `scripts/test-watcher-provider.sh` (new) exits zero and shows the triage call site invokes a non-grok provider with no `grok` on PATH. It fails without the change.
- [ ] `scripts/test-watcher-env.sh` exits zero.
- [ ] `scripts/test-watcher-fence.sh` exits zero.
- [ ] The `tests` job in `.github/workflows/lint.yml` exits zero.
- [ ] Behaviour is unchanged when `FACTORY_PROVIDER` is unset or `grok`.
- [ ] Existing watcher test assertions are not changed (AGENTS.md section 5).
- [ ] The PR body names the watcher test commands run by hand, since `agents.test_command` does not run them.

## Likely files
- `scripts/watcher/watch.sh`, `scripts/watcher/watch.new.sh`
- `scripts/test-watcher-provider.sh`, `scripts/watcher/README.md`, `CHANGELOG.md`

## Out of scope
- Moving any other call site off grok (#399, #400, #401).
- `.github/workflows/**` and existing test assertions.

## Issue text (untrusted)
> Give run_grok a provider seam selected by FACTORY_PROVIDER and move the triage call site onto it. Other call sites keep calling grok for now.
