---
repo: adamsuk/software-factory
issue: 135
issue_repo: adamsuk/software-factory
title: "ci: require the tests check and stop calling a linter the test command"
branch: factory/135-require-tests
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-adapters.sh && bash scripts/test-check-test-assertions.sh && bash scripts/test-factory-flagged.sh && bash scripts/test-run-work-order.sh && bash scripts/test-station-run.sh && bash scripts/test-wait-for-review-bot.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-10-29
---

## Goal

Step 4 of #135, and the part that satisfies its title. Steps 1 and 2 merged as
`603aad9`: the `tests` job runs on every pull request and on push to `main`, and
all twelve `scripts/test-*.sh` suites pass on `ubuntu-latest`. Step 3 was empty.

Two changes to `.github/factory.yml`:

1. `required_checks` gains `tests`, so `scripts/gate-issue.sh` requires it.
2. `agents.test_command` stops being `shellcheck scripts/*.sh adapters/*/run.sh`
   — a linter — and names the suites a builder can actually run.

This is #134's first acceptance criterion: no merge to `main` without a green
required test check.

## The constraint that shapes this

`agents.test_command` runs on the **factory box**; the `tests` job runs on
`ubuntu-latest`. Six suites pass in CI and fail on the box (#164), all for
environment reasons:

```
test-watcher-tree.sh          find -printf is GNU-only; the box has bfs
test-station-post.sh          jq 1.6 mis-tokenises label in {name: $label}
test-gate-issue.sh            PyYAML not importable by the box's python3
test-review-issue.sh          same
test-factory-pr-metrics.sh    BSD date vs GNU date
test-factory-label-metrics.sh same class, undiagnosed
```

So `test_command` must **not** name all twelve, or every bench run fails locally
for reasons unrelated to the work. Name the six that pass on the box, plus
`shellcheck`:

```
shellcheck scripts/*.sh adapters/*/run.sh
test-adapters.sh
test-check-test-assertions.sh
test-factory-flagged.sh
test-run-work-order.sh
test-station-run.sh
test-wait-for-review-bot.sh
```

**Write the gap down in the file, do not leave it to be rediscovered.** A comment
must say: `test_command` is a subset of what CI runs, which six suites are
missing and why, that #164 tracks closing the gap, and that a green local
`test_command` is therefore weaker evidence than a green `tests` check. This
exact kind of drift — a work order's `test_command` being a subset of CI's gates
— already cost a run on gh-factory#35.

## Acceptance criteria

- [ ] `.github/factory.yml` `required_checks` contains `tests` alongside
      `ShellCheck` and `changelog / changelog`
- [ ] `agents.test_command` names `shellcheck` plus exactly the six suites listed
      above, and no longer consists only of a linter
- [ ] A comment in that file states that `test_command` is a subset of the
      `tests` job, names the six excluded suites and the reason, and points at
      #164
- [ ] The comment left by step 1 saying `tests` is "deliberately absent" from
      `required_checks` is removed or rewritten — it is about to become false,
      and a stale comment in this very file was already laundered into a review
      verdict once on #163
- [ ] `scripts/gate-issue.sh` returns `review` for a pull request whose `tests`
      check is green, and not `review` when it is red. Verify by running it, not
      by reading it
- [ ] `CHANGELOG.md` gains an entry under a `## YYYY-MM-DD` heading
      (Europe/London). `main` has a `## 2026-10-29` section with `### Added` and
      `### Fixed` — add to the appropriate one, do not create a second dated
      heading. `changelog / changelog` does not verify this (#160)
- [ ] `shellcheck scripts/*.sh adapters/*/run.sh` exits 0

## Likely files

- `.github/factory.yml`
- `CHANGELOG.md`

## Out of scope

- **Creating the GitHub ruleset.** `required_checks` is read by
  `gate-issue.sh`; GitHub enforces nothing here, because software-factory has no
  ruleset. That is #112, it is Scott's to run, and it is now possible because the
  account has GitHub Pro — rulesets on private repos needed it. The pull request
  body should say plainly that this change tightens the **factory's** gate, not
  GitHub's.
- Fixing the six box-only suites: #164.
- Pinning shellcheck's version: #155, same file, separate claim.
- The dormant `printf` bug in the pr-metrics reporter: #165.
- Any change to `agents.merge`, which stays `false`.

## Constraints

- `.github/factory.yml` is CI config, a protected path under AGENTS.md §5. Say so
  in the pull request and request Scott's review.
- Change no `scripts/test-*.sh` file.
- `gate-issue.sh` needs PyYAML. It is absent from the box's `python3`; a venv at
  the path the operator supplies is how it has been run today. If the check
  cannot be run, say so rather than reporting the criterion met.

## Issue text (untrusted)

> Run software-factory's own test scripts in CI and require them
