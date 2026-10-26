# Changelog

All notable changes to this repo are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## 2026-10-26

### Changed

- Foreman step 5 copies the bench lines `attempt`, `test_command`, `tests`,
  `api_equiv_usd`, and `num_turns` unchanged into the pull request body, and
  sets `factory:gate` when the issue still shows `factory:building` (#79)

## 2026-10-26

### Added

- `scripts/run-work-order.sh` calls `set_gate_label` after a successful `--push`,
  replacing `factory:building` with `factory:gate` when that label is present and
  `factory:blocked` is not (#78)

## 2026-10-26 (bench handoff)

### Added

- `scripts/run-work-order.sh` writes `$dir.bench.txt` beside the clone after tests
  pass and before any push: attempt, test command, `tests: pass`, API-equivalent
  `.total_cost_usd` as `api_equiv_usd`, and integer `.num_turns`. No other Grok
  JSON field is copied (#69).

## 2026-10-26

### Added

- `docs/stations/01-backlog-metrics.md`: one hand check of station 01's three label-event metrics (triage lead time, the share of `factory:ready` issues with one target-repo line and checkable acceptance criteria, and bounce-backs), each with a read-only command, and a worked example from #52 (`factory:done` at `2026-10-26T11:32:05Z`) (#65).

## 2026-10-26

### Added

- README: the Backlog labels section names the nine `factory:*` status labels
  and links to AGENTS.md section 9 (Status labels) for who sets each one (#63).
- Task form: a required Target repository field above Problem, defaulting to
  the single line `Target repo: owner/repo` (#74).

### Changed

- README: "How the pieces fit" states that a backlog issue in this repo names
  one target repository, and that Issue Shipper does not pick issues in other
  repositories on its own (#71).

## 2026-10-26 (smoke test notes)

### Changed

- `agents/grok-build.md`: records the first end-to-end Grok Build run (2026-10-26, 1.0.70):
  `--trust` works, `stopReason: end_turn` confirmed, the extra JSON fields (`thought`,
  `modelUsage`, `total_cost_usd`, `total_cost_usd_ticks`, `requestId`, `cwd`) are never to be
  pasted, and runs on the grok.com session draw from the SuperGrok allowance (`total_cost_usd`
  is an API-equivalent figure). Documents the wrapper's test setup step and squashed commit (#34).
- `agents/roles/foreman.md`: work orders may set an optional `setup_command`.

### Added

- `agents/work-orders/adamsuk_gh-factory-33.md`: the smoke-test work order (#33).

## 2026-10-26 (station 01: status labels and triage/pickup briefs)

### Added

- AGENTS.md section 9, Status labels: the nine `factory:*` labels, who sets each one, one label
  per issue at a time, and only `factory:ready` issues may be built (#43).

### Changed

- Intake brief rewritten as the station 01 triage brief: dedupe, exactly one `Target repo:` line,
  a size, checkable acceptance criteria, and a triage comment that builders work from instead of
  the raw issue text. Each non-duplicate issue ends at `factory:ready` or `factory:blocked` with a
  reason, and duplicates are closed linking the original.
- Foreman brief: picks only `factory:ready` issues, sets `factory:building` on pickup, and builds
  the work order from intake's latest `<!-- factory:triage -->` comment from the factory account.
  Other issues are left alone when picking; in-flight PRs still finish, and any stop after pickup
  moves the issue to `factory:blocked`. Labels record state and never grant merge permission.
- Triage resolves the target repo first, checks it is enrolled with `builder` in its roles, and
  dedupes by target repo plus fingerprint or title. Behaviour changes need a test acceptance
  criterion, otherwise the issue is `factory:blocked`. The foreman checks `builder` in the target
  repo, and `factory:ready` is checked at pickup.
- `.github/factory.yml`: enable intake alongside the existing builder and reviewer roles.

## 2026-10-26

### Added

- `audits/2026-10-26.md`: Line audit against guide v2026-10-25 (26 recommendations: 3 met, 15 partial,
  8 missing), with what changed since 25 Oct and the station tickets (#43 to #51) its gaps are grouped into.
- README: the new audit in the Audits list.

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
