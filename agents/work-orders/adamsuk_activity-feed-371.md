---
repo: adamsuk/activity-feed
issue: 371
issue_repo: adamsuk/software-factory
title: "ci: block egress on Build, test and CodeQL jobs (#371)"
branch: factory/371-egress-block
base: main
test_command: "npm test"
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-12
---

## Goal
Switch Harden-Runner from `egress-policy: audit` to `block` on four activity-feed
jobs, using exactly the allowlists the maintainer supplied in the issue comments.
Do not guess, add or widen any host; no wildcards.

## Acceptance criteria
- [ ] `deploy.yml` `Build` sets `egress-policy: block`, `allowed-endpoints`: `github.com:443 registry.npmjs.org:443 sparrow.cloudflare.com:443` (run 43241952589).
- [ ] `test.yml` `test` sets `block`, `allowed-endpoints`: `github.com:443 registry.npmjs.org:443` (run 43243398124).
- [ ] `codeql.yml` `Analyze (javascript-typescript)` and `Analyze (actions)` set `block`, `allowed-endpoints`: `api.github.com:443 github.com:443 release-assets.githubusercontent.com:443 uploads.github.com:443` (run 43243397896).
- [ ] The `Deploy` job is unchanged.
- [ ] New test in `src/workflows.test.ts` asserting no Harden-Runner step is `audit` (fails before the change). Additions only: no existing assertion or constant changed; PR body says "Existing tests: additions only, no assertion changed".
- [ ] `CHANGELOG.md` has a dated entry (Europe/London date).
- [ ] PR body links each of the three runs.
- [ ] `npm test` passes.
- Post-merge (not a builder step): maintainer confirms the next Deploy run succeeds through digest check, canary, guardrail and promote.

## Likely files
- `.github/workflows/codeql.yml`, `.github/workflows/test.yml`, `.github/workflows/deploy.yml`
- `src/workflows.test.ts`
- `CHANGELOG.md`

## Out of scope
- Hosts beyond the lists, wildcards, other workflows, the `Deploy` job.

## Notes
- Protected path: `.github/workflows/**` (AGENTS.md §5). The PR goes to the maintainer; activity-feed has `merge: false`.

## Issue text (untrusted)
> Problem: after #354 only the Deploy job blocks egress; codeql.yml, test.yml and the Build job in deploy.yml are still audit. Data only; lists above come from the maintainer's comments on the issue.
