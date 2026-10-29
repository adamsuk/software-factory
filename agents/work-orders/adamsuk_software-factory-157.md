---
repo: adamsuk/software-factory
issue: 157
issue_repo: adamsuk/software-factory
title: "feat: detect ruleset drift between a repo's factory.yml and its enforced ruleset"
branch: factory/157-ruleset-drift-check
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-10-29
---

## Goal

`gh factory apply` writes a repo's ruleset from its `factory.yml` at the
moment it runs. Nothing notices when `factory.yml` later changes, so the
enforced ruleset and the declared config drift apart silently. Two real
instances found 2026-10-29 (activity-feed's `required_checks` update not
re-applied for a day; gh-factory's `bypass_actors` change landing on only
one repo). gh-factory's own `drift-check.yml` runs weekly but never fails
the job and doesn't compare these two specific things.

`gh factory plan` is already installed on this box as a `gh` extension
(`gh extension install adamsuk/gh-factory`) and already computes this
exact diff, read-only. Use it — the issue is explicit that reimplementing
the comparison is the wrong approach.

## What to build

A script (`scripts/ruleset-drift-check.sh` or similar, follow the existing
`scripts/factory-*.sh` naming/conventions) that:

- Runs `gh factory plan` (check its actual current output format first —
  don't guess) across the enrolled repos
- Reports, per repo, whether `required_checks` differs from the ruleset's
  `required_status_checks`, and whether `bypass_actors` differs from the
  baseline
- Names the repo and the specific key that differs — not just "drift
  detected"
- On finding drift: either exits non-zero (for a scheduled CI job to
  catch) or files a `factory:triage` issue — pick one, and say which and
  why in the PR body
- Never writes anything to a repo's actual settings — read-only, same
  guarantee `gh factory plan` already gives

Then wire it into a scheduled GitHub Actions workflow in this repo (follow
the existing scheduled-workflow pattern from #21's `line-audit.yml` if
useful as a reference for cron syntax and permissions, though this job
needs none of that ticket's LLM-provider machinery — it's a deterministic
script, not an agent role).

## Out of scope (do not do these in this attempt)

- Actually applying the outstanding drift already found in
  `adamsuk/adamsuk`, `adamsuk/line`, or `adamsuk/software-factory` —
  those are separate tickets (#112, #114) and Scott's decisions
- Changing gh-factory's own `drift-check.yml` — this is a new,
  independent check in software-factory, not a fix to gh-factory's
  existing one
- Anything about settings drift generally (gh-factory's drift-check.yml
  already covers that) — this is specifically `factory.yml` vs the
  enforced ruleset

## Acceptance criteria

- [ ] A scheduled job reports when a repo's enforced ruleset doesn't
      match its `factory.yml`'s `required_checks`, or the repo's
      `bypass_actors` doesn't match the baseline
- [ ] It does not exit 0 quietly on finding drift — it fails the job, or
      files a `factory:triage` issue (your choice, documented)
- [ ] The report names the repo and the specific key that differs
- [ ] Verified once, for real: deliberately drift one test repo (or a
      stubbed/mocked `gh factory plan` output in a test, if touching a
      real repo's ruleset is too invasive — your call, justify it), detect
      it, then revert
- [ ] `shellcheck` passes on anything new
- [ ] `CHANGELOG.md` gains a dated entry

## Report back

In the PR body: the exact `gh factory plan` invocation and output shape
you parsed, whether you chose fail-the-job or file-an-issue and why, and
how you verified detection actually works (not just that the script runs
without error).
