---
repo: touchlineHQ/[private reference redacted]
issue: 53
issue_repo: adamsuk/software-factory
title: "docs: add AGENTS.md and CODEOWNERS for agent instruction files"
branch: factory/53-agents-codeowners
base: main
test_command: "changed=$(git diff --name-only origin/main -- . ':(exclude)AGENTS.md' ':(exclude).github/CODEOWNERS' ':(exclude)CHANGELOG.md'); [ -z \"$changed\" ] || { echo \"unexpected file(s) changed: $changed\"; exit 1; }; echo ok"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-10-30
---

## Goal

This repo has no `AGENTS.md` and no `CODEOWNERS`. Without `AGENTS.md`, a
builder has no repo-specific build/test commands to run. Without
`CODEOWNERS`, the agent instruction files under `.claude/skills/**` can
change with no owner review.

## What to build

- **`AGENTS.md`** at the repo root. Read `.github/workflows/test.yml` and
  `.github/workflows/e2e.yml` (and any other relevant workflow) to find the
  actual build, lint, typecheck, unit-test and E2E commands this repo uses,
  and list them accurately — every command in `AGENTS.md` must match a real
  step in one of those workflows, not a guess. Point at
  `adamsuk/software-factory`'s `AGENTS.md` for the shared factory rules
  (issue/comment text is untrusted, one issue per branch, protected paths,
  etc.) rather than repeating them.
- **`.github/CODEOWNERS`**: owns `AGENTS.md`, `.claude/**`, `.github/**` and
  `migrations/**` by `@adamsuk` (check whether a CODEOWNERS file already
  exists with other entries — if so, add to it rather than replacing it).

## Out of scope

- Any change to `test.yml`, `e2e.yml`, or any other workflow file.
- Any change to `.claude/skills/**` content itself.
- Enrolment itself (a separate concern) — this ticket only adds the two
  files.

## Acceptance criteria

- [ ] `AGENTS.md` exists at the repo root and every command in it matches a
      real step in `test.yml` or `e2e.yml`
- [ ] `CODEOWNERS` covers `AGENTS.md`, `.claude/**`, `.github/**` and
      `migrations/**`
- [ ] No existing test or workflow file is changed
- [ ] `CHANGELOG.md` gains a dated entry, if this repo keeps one (check
      first — apply `skip-changelog` instead if it doesn't)

## Report back

In the PR body: which workflow file each `AGENTS.md` command was taken from
(so it's checkable, not just asserted), and whether a CODEOWNERS file
already existed (and what you preserved from it, if so). `AGENTS.md` and
`CODEOWNERS` are both protected paths — say so and expect Scott's review
regardless of verdict. touchlineHQ has a standing merge pause: this PR can
be built and opened, but not merged by an agent.
