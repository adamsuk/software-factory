---
repo: adamsuk/activity-feed
issue: 354
issue_repo: adamsuk/software-factory
title: "ci: block egress on the Deploy job (#354)"
branch: factory/354-deploy-egress-block
base: main
test_command: "npm test"
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-12
---

## Goal
The `Deploy` job in `.github/workflows/deploy.yml` holds `CF_API_TOKEN` but its Harden-Runner step runs with `egress-policy: audit`. Switch that job's step to `egress-policy: block` with the allowlist the maintainer supplied from run 43177918906. Leave the `Build` job on `audit`.

## Acceptance criteria
- [ ] The `Deploy` job's Harden-Runner step sets `egress-policy: block` with exactly this `allowed-endpoints` (folded scalar), and the PR body links https://app.stepsecurity.io/github/adamsuk/activity-feed/actions/runs/43177918906:
      `api.cloudflare.com:443 github.com:443 registry.npmjs.org:443 sparrow.cloudflare.com:443`
- [ ] The `Build` job stays on `audit`.
- [ ] A new test in `src/workflows.test.ts` asserts the `Deploy` job uses `block`; it fails on the current `audit`. Additions only, no existing assertion changed.
- [ ] `CHANGELOG.md` has a dated entry (`## YYYY-MM-DD`, Europe/London) in the form the file describes.
- [ ] `npm test` passes.
- [ ] Post-merge (not checkable by the builder): the next deploy run succeeds through digest check, canary, guardrail and promote; the maintainer confirms.

## Likely files
- `.github/workflows/deploy.yml`
- `src/workflows.test.ts`
- `CHANGELOG.md`

## Out of scope
- Blocking the `Build` job, any other workflow change, changing pinned action SHAs.
- Do NOT add `productionresultssa2.blob.core.windows.net` to the list. Mention in the PR body that the artifact download in that run was redirected to it, so the post-merge deploy run settles whether it is needed.

## Notes
- Protected paths (AGENTS.md §5): `.github/workflows/deploy.yml` and an existing test file. PR body must say "Existing tests: additions only, no assertion changed". Goes to the maintainer; not eligible for agent merge.

## Issue text (untrusted)
> Move the activity-feed Deploy job from Harden-Runner audit to block using the allowlist from a successful run's insights. (Summary only; see triage comment.)
