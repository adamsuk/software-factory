---
repo: adamsuk/software-factory
issue: 106
issue_repo: adamsuk/software-factory
title: "fix: require Target repo line in filed issues; correct the work order's file-list claim"
branch: factory/106-research-files-issues
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh"
setup_command: ""
changelog: false
merge_allowed: false
review_bot: coderabbit
attempt: 2
created: 2026-10-30
---

## Goal

CodeRabbit found two small but real issues in PR #192:

1. `agents/roles/research.md`'s Steps section lists what each filed issue
   must contain, but doesn't require a `Target repo: owner/repo` line.
   `agents/roles/intake.md` requires that line for `factory:triage` issues
   — without it, intake can leave Research Scout's own issues stuck instead
   of routing them to the builder.
2. The work order file itself
   (`agents/work-orders/adamsuk_software-factory-106.md`) has an acceptance
   criterion saying "the only files changed are `agents/roles/research.md`
   and `CHANGELOG.md`" — but the work order file is itself a changed file
   in that same PR, so the claim is false as written.

## What to change

- `agents/roles/research.md`: add a `Target repo: owner/repo` line naming
  where the change lands to the list of what each filed issue must contain
  (alongside the dated sources, guide section, proposed change, and the
  CHANGELOG/collapsible-sections line already there).
- `agents/work-orders/adamsuk_software-factory-106.md`: reword the
  file-list acceptance criterion to exclude the work order file itself —
  e.g. "Apart from this work order, the only implementation files changed
  are `agents/roles/research.md` and `CHANGELOG.md`."

## Out of scope

- Anything else in `research.md` or the PR.

## Acceptance criteria

- [ ] `agents/roles/research.md` requires a `Target repo: owner/repo` line
      in every filed issue
- [ ] The work order's file-list claim no longer contradicts its own
      presence in the diff
- [ ] `shellcheck` stays clean

## Report back

No changelog entry needed (the existing dated entry for #106 already
covers this). This is a two-line wording fix, no test needed beyond
shellcheck.
