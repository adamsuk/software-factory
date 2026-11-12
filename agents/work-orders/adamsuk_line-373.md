---
repo: adamsuk/line
issue: 373
issue_repo: adamsuk/software-factory
title: "ci: block egress on the pages.yml deploy job (#373)"
branch: factory/373-pages-deploy-block
base: main
test_command: "npm run typecheck && npm run lint && npm run test:factory"
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-12
---

## Goal
Switch the `pages.yml` `deploy` job's Harden-Runner step to `egress-policy: block` with the allowlist the maintainer took from main run 43043623745 (`api.github.com:443`), and remove that job's exemption from the guard test `src/factory/egress.test.ts`.

## Acceptance criteria
- [ ] `pages.yml` `deploy` blocks egress with exactly `api.github.com:443`, and the PR links run 43043623745.
- [ ] `src/factory/egress.test.ts` no longer exempts `pages.yml:deploy`; only that named exemption is removed (approved by the maintainer), no other assertion changed.
- [ ] `npm run typecheck && npm run lint && npm run test:factory` passes.
- [ ] `CHANGELOG.md` has a dated entry.
- [ ] After merge (maintainer): approve `github-pages` and confirm the next Pages run succeeds through deploy.

## Notes
- Protected path (AGENTS.md section 5): `.github/workflows/pages.yml`. Goes to the maintainer.
