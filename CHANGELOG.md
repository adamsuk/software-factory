# Changelog

All notable changes to this repo are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## 2026-10-26 (test environment setup)

### Added

- `scripts/run-work-order.sh` prepares the target repo's test environment before
  `test_command`. A work order `setup_command` wins, otherwise `agents.setup_command`
  from `.github/factory.yml` on `origin/$base` (not the working tree), otherwise a
  Python venv outside the clone or a Node install (`pnpm` or `yarn` with a frozen
  lockfile, `npm ci`, or `npm install --no-package-lock`). For a `pyproject.toml`,
  the venv installs the project editable with the `dev` and `test` extras declared
  in `[project.optional-dependencies]` (`-e '.[dev,test]'`, `-e '.[dev]'`,
  `-e '.[test]'`, or `-e .`). A `setup.py` without `pyproject.toml` installs
  `-e .`. Setup failure exits 6.
  A setup that changes tracked files, moves `HEAD` or changes its tree exits 4.
  The environment a custom setup command exports (for example an activated venv
  or a `PATH` change) carries into `test_command`. On Python 3.10, extras are read
  with `tomli` or pip's vendored copy, and skipped with a message if neither exists.

### Changed

- `scripts/run-work-order.sh` turns Grok Build's commits and any leftover changes
  into one commit on top of the starting revision, titled `<title> (#<issue>)`.
  Commits that were already on the remote branch are left as they are.

## 2026-10-26 (agent merges off)

### Changed

- `.github/factory.yml`: `agents.merge: false`. Required checks and branch protection can't be
  enforced on the Free plan while the repo is private, so agent merges stay off until a ruleset
  enforces required checks and branch protection on main.

## 2026-10-26 (CodeRabbit approvals)

### Added

- `.coderabbit.yaml` turns on CodeRabbit's approve/request-changes workflow
  (`reviews.auto_approvals.enabled: true`), so CodeRabbit posts APPROVED or CHANGES_REQUESTED
  reviews instead of only COMMENTED ones and its approval can be one part of the sign-off gate.

### Changed

- AGENTS.md section 5: `.coderabbit.yaml` is a protected path, so changes to CodeRabbit's
  config go to Scott.

## 2026-10-25 (rule fixes from the gh-factory#16 trial)

### Changed

- AGENTS.md section 5: a builder may add fixture or test data to an existing test without Scott's
  review if no existing assertion is changed, removed or weakened and the PR body says so.
  Changing assertions or deleting tests still needs Scott. The reviewer brief checks this.
- AGENTS.md section 6: merging also needs the review gate for the repo's `agents.review_bot`.
  `coderabbit` needs no blocking CodeRabbit findings plus PR Reviewer's review; `none` (the
  default) needs PR Reviewer's review with no unresolved should-fix items. Required checks must
  still be green, and the touchlineHQ merge pause is unchanged.
- Builder brief: run `agents.test_command` before opening a PR (or read CI and name the command in
  the PR body), and reference issues as `#N` in the same repo or `owner/repo#N` in another repo.
  A `Refs` issue in another repo is closed by hand after its PR merges.
- Intake brief: every issue names where the change lands in a `Target repo: owner/repo` line,
  plus an existing `repo:<name>` label where one fits. The foreman brief reads that line.

### Added

- `.github/factory.yml`: `agents.review_bot: coderabbit` and `agents.test_command: shellcheck scripts/*.sh`
  (keys from adamsuk/gh-factory#18).

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
