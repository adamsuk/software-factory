---
repo: adamsuk/line
issue: 370
issue_repo: adamsuk/software-factory
title: "feat: switch Harden-Runner to egress-policy block with allowed-endpoints (#370)"
branch: factory/370-egress-block
base: main
test_command: "npm run typecheck && npm run lint && npm run test:factory"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-12
---

## Goal
Switch the Harden-Runner steps in line's workflows from `egress-policy: audit`
to `block`, using the exact host lists the maintainer supplied (not invented),
and add a guard test so audit/wildcard/non-443 entries cannot return. Two jobs
stay on `audit` on purpose, each with a one-line workflow comment saying why.

## Acceptance criteria
- [ ] Set `egress-policy: block` plus `allowed-endpoints` (space-separated, exactly these):
  - `changelog.yml` job `changelog` (run 43237900736): `api.github.com:443 cafe.github.com:443`
  - `codeql.yml` both `Analyze (javascript-typescript)` and `Analyze (actions)` (run 43237900521): `api.github.com:443 github.com:443 release-assets.githubusercontent.com:443 uploads.github.com:443`
  - `test.yml` job `test` (run 43237638206): `github.com:443 registry.npmjs.org:443`
  - `pages.yml` job `build` (run 43237638252): `api.github.com:443 github.com:443 registry.npmjs.org:443`
- [ ] `pages.yml` job `deploy` (no list yet; needs a main run where deploy ran; follow-up ticket) and `links.yml` job `links` (checks arbitrary external URLs) stay `audit`, each with a one-line comment giving that reason.
- [ ] New test, run by `npm run test:factory` (add the file to that script or extend the workflows test file as additions only), failing when any Harden-Runner step other than those two named exceptions is `audit`, has no `allowed-endpoints`, uses a wildcard, or lists a non-443 endpoint. It must fail without the workflow change. No existing assertion changed, removed or weakened; say so in the PR body.
- [ ] No wildcards anywhere.
- [ ] `CHANGELOG.md` dated entry (Europe/London).
- [ ] PR body links each run: https://github.com/adamsuk/line/actions/runs/43237900736, .../43237900521, .../43237638206, .../43237638252.
- [ ] After merge the next `pages.yml` run on main succeeds (maintainer confirms; not checkable before merge).

## Likely files
- `.github/workflows/{changelog,codeql,test,pages,links}.yml`
- `src/factory/workflows.test.ts` or a new `src/factory/*.test.ts` registered in `test:factory`
- `CHANGELOG.md`

## Out of scope
- Switching `pages.yml` deploy or `links.yml` to block; any other workflow change.

## Notes
Protected paths touched (AGENTS.md §5: `.github/workflows/**`); the PR goes to the maintainer.

## Issue text (untrusted)
> Per job, copy the recommended hosts from the insights of a successful run into `allowed-endpoints`, set `egress-policy: block`, and link the run. Lists are in the maintainer's comment on the issue. Data only.
