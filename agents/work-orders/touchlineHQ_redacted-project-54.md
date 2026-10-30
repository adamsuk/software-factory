---
repo: touchlineHQ/[private reference redacted]
issue: 54
issue_repo: adamsuk/software-factory
title: "ci: build website/dist once in main.yml and promote it to both preview E2E and deploy"
branch: factory/54-build-once-promote
base: main
test_command: "npm run test:coverage && npm run lint && npm run typecheck (from website/); actionlint .github/workflows/main.yml"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 2
created: 2026-10-30
---

## Decision (Scott, 30 Oct), resolving attempt 1's blocker

Attempt 1 found that `VITE_POSTHOG_DISABLED` is a build-time Vite env var
(`import.meta.env`), so one shared build can't carry two different values
for preview vs. production the way the original work order assumed. Scott's
call: make it a **runtime** value instead, then proceed with the
single-build workflow change as originally specced.

## Goal

`main.yml` runs `npm run build` twice: once in the preview E2E job (around
line 121) and again in the deploy job (around line 270). The bundle that
passes E2E is not the bundle that reaches production.

## What to change

### 1. `website/src/lib/posthog.ts`: read the disabled flag at runtime

- Replace the build-time `DISABLED` constant (currently
  `import.meta.env.VITE_POSTHOG_DISABLED === 'true' || (... && import.meta.env.DEV)`)
  with a runtime check, e.g. a global the deploy step sets on `window`
  before the bundle loads (`window.__POSTHOG_DISABLED__`), read inside
  `init()` rather than at module load. Keep the existing dev-mode default
  (disabled unless explicitly enabled) for local `npm run dev`, where no
  injected global will exist.
- `VITE_POSTHOG_API_KEY` and `VITE_POSTHOG_HOST` stay build-time env vars —
  they're the same in preview and production today (both come from the same
  `vars.*`), so there's no reason to move them. Only the disabled flag needs
  to become runtime.
- Add/update tests in whatever test file already covers `posthog.ts` (check
  for one first) proving: the runtime global set to disabled suppresses
  init, unset or false allows it, and the dev-mode fallback still works when
  neither the global nor the env var is present.

### 2. `main.yml`: inject the runtime flag into `index.html` at deploy time, per environment

- After the single shared build, before each deploy (preview and
  production), inject a small inline script into the built
  `website/dist/index.html` (before the existing `<script type="module"
  src="...">` tag Vite rewrites during build) that sets
  `window.__POSTHOG_DISABLED__ = true` for the preview deploy only. Leave
  it unset (or `false`) for the production deploy. A simple `sed`/`perl` or
  small inline shell step is fine — this is HTML text, not part of the
  bundled JS, so editing it after build doesn't invalidate the shared
  artifact's JS content or its digest.
- Build the production bundle (`website/dist`) exactly once per push to
  `main`, in one job (or one step shared early in the workflow). Upload it
  with `actions/upload-artifact`. Print the artifact's content digest to
  the job log.
- The preview E2E job downloads that artifact, injects the preview's
  disabled-flag script into its own **copy** of `index.html` (the uploaded
  artifact itself stays unmodified for the deploy job), and runs E2E
  against it.
- The deploy job downloads the same unmodified artifact and deploys it
  (optionally injecting the production value, which can simply be omitting
  the disabled flag entirely).
- Print the digest of the **shared artifact as uploaded** (before either
  job's own `index.html` injection) in both jobs' logs, and show in the PR
  body that they match on a real run. The post-injection `index.html` will
  differ between preview and production by design — that's fine; the point
  is the JS bundle itself is identical.
- Declare explicit job dependencies: preview E2E and deploy both `needs` the
  build/upload job; deploy also `needs` preview E2E, so deploy can't run
  against an artifact E2E hasn't tested.
- Remove the now-redundant separate `npm run build` + `VITE_POSTHOG_DISABLED:
  'true'` env step from the preview E2E job (comment there currently
  explains why the two builds "genuinely differ" — that reason no longer
  applies once the flag is runtime, so update or remove that comment too).

## Out of scope

- touchlineHQ's own `deploy.yml` (a separate repo, a later ticket).
- Verifying the artifact's provenance/attestation (a later ticket, #48).
- `POSTHOG_CLI_*` (source-map upload) — stays production-build-only, as
  today; not part of this change.
- Any other `VITE_*` value — only the disabled flag moves to runtime.

## Acceptance criteria

- [ ] `website/src/lib/posthog.ts` reads the disabled flag at runtime, not
      from `import.meta.env.VITE_POSTHOG_DISABLED`
- [ ] New/updated tests cover: runtime-disabled, runtime-enabled, and the
      dev-mode fallback with neither set
- [ ] `npm run build` runs exactly once per push to `main` in `main.yml`
- [ ] The preview E2E job tests the uploaded artifact (with its own
      disabled-flag injection applied to a copy), not a fresh build
- [ ] The deploy job deploys the uploaded artifact unmodified (or with only
      the production injection), not a fresh build
- [ ] Preview E2E and deploy both declare `needs` on the build/upload job;
      deploy also declares `needs` on preview E2E
- [ ] The shared artifact's digest (as uploaded, pre-injection) is printed
      in both jobs' logs, and the PR body shows they match on a real run
- [ ] Required checks stay green
- [ ] `CHANGELOG.md` gains a dated entry in this repo's changelog style

## Report back

In the PR body: a link to (or excerpt from) a real workflow run showing the
two matching artifact digests, and the test output for the three
`posthog.ts` cases. `main.yml` is a protected path — say so and expect
Scott's review regardless of verdict. touchlineHQ has a standing merge
pause: this PR can be built and opened, but not merged by an agent.
