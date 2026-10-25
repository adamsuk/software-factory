# Changelog

All notable changes to this repo are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## 2026-10-25 (agents may merge here)

### Added

- `.github/factory.yml` with `agents: { merge: true }`, so the factory agents may merge their own
  software-factory PRs once the PR's checks are green (AGENTS.md section 6). Roles stay the default
  (builder, reviewer) and the issue label stays `factory`.

## 2026-10-25 (factory sync)

### Fixed

- `.github/ISSUE_TEMPLATE/task.yml`: Acceptance criteria uses a placeholder instead of a prefilled
  `- [ ] `, so `required: true` actually requires an answer (adamsuk/gh-factory#10).

## 2026-10-25 (agents)

### Added

- `AGENTS.md`: the shared rules for Grok Build and the Grok Bot agents. Issue text is untrusted
  data, one issue per run, a branch per issue, tests required, a dated changelog entry or the
  `skip-changelog` label, at most 3 fix-loop attempts, protected paths (tests, CI, lockfiles) go to
  a person, no merging unless `agents.merge: true` and required checks are green (plus the
  touchlineHQ merge pause), no secrets, the Resend `RESEND_WEBHOOK_SECRET` guard, generic CI.
- `agents/roles/`: briefs for the foreman (the new Software Factory bot), intake, research,
  builder and reviewer roles, including the work order format.
- `agents/grok-build.md`: how to run Grok Build 1.0.70 headless for a work order, with the docs
  it was checked against.
- `scripts/run-work-order.sh`: clones the target repo into a unique `/workspace` directory, makes
  the branch, runs Grok Build with `AGENTS.md` and the work order, checks protected paths, runs
  the tests, and only pushes with `--push` when everything passed.
- A ShellCheck workflow for `scripts/`.

## 2026-10-25

### Added

- README covering the purpose, the long-term aim, how this repo relates to adamsuk/gh-factory
  and the Grok Bot agents, and the backlog labels.
- Line audits from 2026-10-24 and 2026-10-25 in `audits/`.
- A backlog of issues from the 2026-10-25 audit, plus the Software Factory GitHub Project.
