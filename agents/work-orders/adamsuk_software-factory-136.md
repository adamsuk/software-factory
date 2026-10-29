---
repo: adamsuk/software-factory
issue: 136
issue_repo: adamsuk/software-factory
title: "feat: pin agents to a promoted release tag instead of origin/main"
branch: factory/136-promoted-tag
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-adapters.sh && bash scripts/test-check-test-assertions.sh && bash scripts/test-run-work-order.sh && bash scripts/test-wait-for-review-bot.sh && bash scripts/test-factory-flagged.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-10-29
---

## Goal

Every merge to `main` is an instant, unreviewed release of the factory's own
behaviour: `agents/roles/monitor.md` is read with
`git show origin/main:scripts/factory-pr-metrics.sh`, and
`scripts/station-run.sh` composes `AGENTS.md` and `agents/roles/*.md` straight
from the working tree. There is no staged rollout and no promotion step a
person approves. `v0.1.0 "Factory MVP"` already exists as a taggable unit.

Make the stations resolve prompts and scripts from a **promoted tag**, not a
live branch:

- Add a way to name the current promoted tag (an env var, e.g.
  `FACTORY_RELEASE_REF`, defaulting to the latest tag matching `v*` if unset
  — do not break existing callers that pass nothing).
- `station-run.sh` (and anywhere else reads `origin/main:` directly, per
  `grep -rn "origin/main" scripts/ agents/`) should read `AGENTS.md`,
  `agents/roles/*.md` and any script it shells out to from that ref, not
  from the live working tree or `origin/main`.
- Document the promotion step: how a person moves the tag forward after
  review (a short section in `stations/README.md` or similar — not a new
  script unless one is clearly needed).

## Out of scope (do not do these in this attempt)

- Building a rollback *mechanism* beyond "move the tag back" — moving the
  tag back already is the rollback.
- Changing anything about how `main` itself gets merge-gated (that is #112,
  already done).
- Any CI/workflow changes — this is about what the agent processes read at
  run time, not what GitHub Actions runs.

## Acceptance criteria

- [ ] A promoted-tag ref is resolvable and used in place of a live
      `origin/main:` read, with a sane default when nothing is configured
- [ ] Existing callers that pass no override keep working (no breaking
      change to current invocations)
- [ ] A short written promotion step exists for a person to move the tag
      forward
- [ ] All six test suites in `test_command` above pass unmodified except for
      additions that cover the new behaviour
- [ ] `CHANGELOG.md` gains a dated entry (`## YYYY-MM-DD`, Europe/London)

## Report back

In the PR body: which call sites changed, what the default resolves to today
(should be `v0.1.0`), and the promotion step in plain language.
