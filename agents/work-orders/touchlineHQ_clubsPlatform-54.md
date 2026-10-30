---
repo: touchlineHQ/clubsPlatform
issue: 54
issue_repo: adamsuk/software-factory
title: "ci: build website/dist once in main.yml and promote it to both preview E2E and deploy"
branch: factory/54-build-once-promote
base: main
test_command: "actionlint .github/workflows/main.yml"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-10-30
---

## Goal

`main.yml` runs `npm run build` twice: once in the preview E2E job (around
line 121) and again in the deploy job (around line 270). That means the
bundle that passed E2E is not the bundle that reaches production — a
regression could pass E2E against one build and ship a different one.

## What to change

- Build the production bundle (`website/dist`, or whatever the build step
  currently produces) exactly once per push to `main`, in one job (or one
  step shared early in the workflow).
- Upload it with `actions/upload-artifact`. Print the artifact's content
  digest (e.g. `sha256sum` over the built output, or whatever
  `actions/upload-artifact`'s own digest output gives you) to the job log.
- The preview E2E job downloads that artifact (via `actions/download-artifact`)
  and runs E2E against it, instead of building its own copy.
- The deploy job downloads the **same** artifact and deploys it, instead of
  running `npm run build` again.
- Print the digest in both the E2E job and the deploy job's logs, and make
  sure they're the same value (that's the proof the two jobs used the
  identical artifact).
- If preview and production need different `VITE_*` environment values,
  say so explicitly in the PR body, and keep the difference to injected
  config only (e.g. a separate config file read at runtime, or env vars
  injected at deploy time) — not a different build.

## Out of scope

- touchlineHQ's own `deploy.yml` (a separate repo, a later ticket).
- Verifying the artifact's provenance/attestation (a later ticket, #48).
- Any change to what gets built (asset content, build tool, dependencies).

## Acceptance criteria

- [ ] `npm run build` (or equivalent) runs exactly once per push to `main`
      in `main.yml`
- [ ] The preview E2E job tests the uploaded artifact, not a fresh build
- [ ] The deploy job deploys the uploaded artifact, not a fresh build
- [ ] The artifact's digest is printed in both the E2E job and the deploy
      job's logs, and the PR body shows they match on a real run
- [ ] Required checks stay green
- [ ] `CHANGELOG.md` gains a dated entry in this repo's changelog style

## Report back

In the PR body: a link to (or excerpt from) a real workflow run showing the
two matching digests, and confirm whether preview/production need different
`VITE_*` values and how you kept that to injected config only. `main.yml` is
a protected path (`.github/workflows/**`) — say so and expect Scott's
review regardless of verdict. touchlineHQ has a standing merge pause: this
PR can be built and opened, but not merged by an agent.
