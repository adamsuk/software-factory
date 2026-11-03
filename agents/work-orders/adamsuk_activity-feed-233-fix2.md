---
repo: adamsuk/activity-feed
issue: 233
issue_repo: adamsuk/software-factory
title: "fix: add a concurrency group to the gated production deploy"
branch: factory/233-production-environment
base: main
test_command: "npm test"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 2
created: 2026-11-03
---

## Goal

PR adamsuk/activity-feed#30's independent review (FIX verdict) found a real
gap: the `deploy` job now waits on the `production` environment's required
reviewer, but with no concurrency group, an older deploy that's still
sitting in that approval queue could be approved and run *after* a newer
one, overwriting it.

## What to change

In `.github/workflows/deploy.yml`, add a job-level `concurrency` block to
the `deploy` job:

```yaml
    concurrency:
      group: production
      cancel-in-progress: false
```

`cancel-in-progress: false` on purpose: a deploy already approved and
running should finish, not be killed mid-deploy by a newer push arriving —
the next push's run queues behind it instead of cancelling it, which is
the same "don't overwrite in-flight work" intent as the review's finding.

## Out of scope

- Anything else about `deploy.yml` — the environment gate and rollback
  docs from round 1 are correct and already built; don't touch them.
- The not-yet-blocking CodeRabbit note about `permissions: contents: read`
  being a pre-existing default — the review itself marked that as not
  blocking.

## Acceptance criteria

- [ ] The `deploy` job has a `concurrency` block with `group: production`
      and `cancel-in-progress: false`
- [ ] `npm test` still passes
- [ ] `CHANGELOG.md` gains a line noting this (or amends the existing
      round-1 entry if that reads better — your call, say which in the
      report)

## Constraints

- `.github/workflows/**` is a protected path (AGENTS.md §5) — unchanged
  from round 1, already noted in the PR.

## Report back

Confirm the exact YAML added and its placement (must be on the `deploy`
job, not workflow-level).
