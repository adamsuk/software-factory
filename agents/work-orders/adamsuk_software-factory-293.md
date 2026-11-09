---
repo: adamsuk/software-factory
issue: 293
issue_repo: adamsuk/software-factory
title: "docs: replace personal name, fixed slugs and machine paths with placeholders"
branch: factory/293-docs-placeholders
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-adapters.sh && bash scripts/test-check-test-assertions.sh && bash scripts/test-factory-flagged.sh && bash scripts/test-run-work-order.sh && bash scripts/test-run-work-order-llm.sh && bash scripts/test-station-run.sh && bash scripts/test-wait-for-review-bot.sh && bash scripts/test-research-brief.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-09
---

## Goal

Make the published docs usable on any machine and for any owner. Replace the maintainer's personal name, hard-coded owner/repo slugs in command examples, and machine-specific absolute paths in docs with neutral wording or placeholders. This changes no behaviour.

Size: S/M (docs and code comments only, no protected paths)

## Scope

- `README.md`:
  - Change the opening line from the maintainer's personal possessive to "An end-to-end software factory".
  - Elsewhere, refer to the maintainer by role ("the maintainer") instead of by personal name.
  - Remove the rows and sentences about the private delivery organisation, or generalise them to "other enrolled organisations".
  - Replace the two GitHub Project board links with "your GitHub Project board" plus a one-line setup note.
  - **Keep** the canonical links to `adamsuk/software-factory`, `adamsuk/gh-factory` and `adamsuk/line`, which are the public upstreams.
- `stations/run-factory.md`, `stations/github-writes.md`, `stations/README.md` and `stations/run-factory-quirks.md`:
  - Replace hard-coded `owner/repo` slugs in commands and examples with `<owner>/<repo>`, or with `$FACTORY_HOME_REPO` where a variable reads better.
  - Write the clone root as `$FACTORY_WORKSPACE` instead of a fixed absolute directory.
  - Refer to the maintainer by role.
- `docs/stations/01-backlog-metrics.md`: change `/repos/<fixed owner>/software-factory/...` to `/repos/<owner>/<repo>/...`, and use relative `#N` issue references.
- `.claude/skills/run-factory/SKILL.md`: drop the hard-coded repo slug from the description.
- `agents/work-orders/README.md`: write the example file name as `<owner>_<repo>-<issue>.md`.
- Code comments only, with no output strings or behaviour changed: `adapters/claudecode/run.sh` (the model-default comment) and the header comments of `scripts/factory-flagged.sh` and `scripts/watcher/autopush.sh`. Refer to the maintainer by role.

## Acceptance criteria

- [ ] In the files listed above, the maintainer's personal name no longer appears. `git grep -n "Scott"` on those paths returns nothing.
- [ ] In those files, `adamsuk` appears only in the kept canonical links to `adamsuk/software-factory`, `adamsuk/gh-factory` and `adamsuk/line`.
- [ ] In those files, no hard-coded `/home/...` or `/workspace` path remains, except when it is shown as the value of an env var example.
- [ ] The private delivery organisation is not named in `README.md`.
- [ ] No script output string or behaviour changes.
- [ ] `CHANGELOG.md` gains exactly one new dated entry (Europe/London date) for this change. Existing CHANGELOG entries are not edited.
- [ ] These are not edited: `audits/`, `metrics/`, existing `agents/work-orders/*_*.md` records, `LICENSE`, `AGENTS.md`, `agents/roles/**`, `agents/grok-build.md`, `.github/**`, `.coderabbit.yaml` and tests.
- [ ] `agents.test_command` passes. So do `bash scripts/test-watcher-tree.sh` and `bash scripts/test-research-brief.sh`, which read docs.

## Out of scope

- Script defaults and env vars. Those are a separate issue.
- Protected agent instructions and CI wording. Those are a separate issue.
- Approving or merging. The maintainer does that.

## Builder notes

- Only docs and code comments change. Do not touch script output strings.
- Add this work order as `agents/work-orders/adamsuk_software-factory-293.md` (bookkeeping copy of this file).
- Commit with a conventional message ending `(#293)`. Do not push, open PRs, or call `gh`; the runner does that.
- Run `agents.test_command` plus any extra test named in the acceptance criteria before finishing.
- Do not write the private delivery organisation's name anywhere (commit message, CHANGELOG, comments).
