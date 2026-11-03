---
repo: adamsuk/activity-feed
issue: 233
issue_repo: adamsuk/software-factory
title: "ci: gate activity-feed's deploy behind a production environment"
branch: factory/233-production-environment
base: main
test_command: "npm test"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-03
---

## Goal

`.github/workflows/deploy.yml`'s `deploy` job runs the Cloudflare Wrangler
deploy with no named approval gate. Give it a `production` GitHub
Environment so a deploy can require a reviewer, and document how to roll
back without needing a second approval.

## What to change

1. **`.github/workflows/deploy.yml`**: add `environment: production` to the
   `deploy` job (same job that already has `secrets.CF_API_TOKEN` — don't
   move the secret or add a second job).
2. **Document rollback steps** that can run without a second approval — for
   example, re-running the previous successful `Deploy` workflow run (or
   re-deploying the previous commit's build) via `gh run rerun` or
   `wrangler` directly, without going through this gated job again. Put
   this wherever the repo's docs/README already describe operations (check
   first — don't invent a new doc file if one fitting already exists), or
   as a new short `docs/rollback.md` if nothing fits. State clearly that
   rollback bypasses the `production` environment's approval, and why
   that's the point (a stuck pending approval shouldn't block an urgent
   rollback).
3. **`CHANGELOG.md`**: dated entry.

**The GitHub repo setting itself — creating the `production` environment
with adamsuk as a required reviewer — is Scott's to do, not this build's.**
The issue says so explicitly ("setting, applied by Scott or noted in the
PR"). Referencing an environment name in the workflow that doesn't exist
yet in the repo's Settings just auto-creates a bare one with no protection
rule the first time it runs — that's expected; note it plainly in the PR
body rather than treating it as blocking.

## Out of scope

- touchlineHQ repos' production-environment work (#11, #49) — different
  repos, already covered elsewhere.
- Any other hardening of `deploy.yml` beyond the environment gate (Harden-
  Runner is a separate issue, #224).

## Acceptance criteria

- [ ] The wrangler deploy job declares `environment: production`
- [ ] Rollback steps are documented and explicitly don't need a second
      approval
- [ ] `CHANGELOG.md` has a dated entry
- [ ] `npm test` passes
- [ ] The PR body states plainly that the environment's required-reviewer
      setting itself is Scott's to configure

## Constraints

- `.github/workflows/**` is a protected path (AGENTS.md §5). Say so in the
  PR body; Scott reviews it regardless of verdict.
- `adamsuk/activity-feed#27` (adamsuk/software-factory#224) is an open PR
  on the same repo also touching `deploy.yml` (adding a Harden-Runner
  step), from the same `main`. A small rebase conflict between the two is
  expected and fine — not a reason to avoid this change.

## Issue text (untrusted)

> The Line audit of 2026-11-03 (`human-release-gate`, quick win) found
> activity-feed's wrangler deploy step runs outside any environment, so a
> production deploy needs no named approval. #11 and #49 cover touchlineHQ
> repos only.
>
> Run the wrangler deploy job in a `production` environment with adamsuk as
> required reviewer, and document rollback steps in the same change.

## Report back

Confirm the environment line was added to the right job (the one with
`CF_API_TOKEN`), where the rollback steps were documented, and restate that
the required-reviewer setting itself needs Scott.
