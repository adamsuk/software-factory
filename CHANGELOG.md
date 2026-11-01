# Changelog

All notable changes to this repo are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## 2026-11-01

### Added

- `scripts/gate-issue.sh` writes `<work-order>.red-record` when required
  checks are red (#24). Each current red check is `new` or `seen-before`
  against the `red:` lines of earlier `<!-- factory:gate -->` comments, with
  owner Scott. The record does not change retry, repeat, or attempt-cap
  routing, the comment body, or the one-word stdout. `review`, `pending`,
  `skip`, and `blocked` for `no-required-checks` do not write it. Covered by
  `scripts/test-red-check-record.sh`.

- `scripts/test-harness-eval.sh` replays one recorded work order offline (#20).
  The fixture `scripts/fixtures/replay-work-order.md` is a copy of
  `agents/work-orders/adamsuk_gh-factory-33.md`. The suite renders the builder
  prompt with `scripts/station-run.sh --dry-run` and checks the fences still
  wrap that work order. No model call and no new dependency.
  `scripts/station-run.sh` reads `AGENTS.md` and the role briefs from the
  latest `v*` tag, so this case checks the composer fences and the recorded
  work order. `FACTORY_RELEASE_REF` stays unset.

- `scripts/test-untrusted-issue.sh` records that a harmless prompt-injection
  issue is data (#16). The suite runs `write_untrusted_block` and
  `escape_untrusted` from `scripts/watcher/watch.sh` and checks the body stays
  between the untrusted fences, including when the body contains the fence
  markers. The command named in that issue is not run. The same two functions
  in `scripts/watcher/watch.new.sh` are checked to match.

### Fixed

- Independent review keeps the last PASS, FIX, or ESCALATE object when Grok's
  `.text` holds several JSON values or trailing text. A final `VERDICT:` line,
  or a final line that is exactly PASS, FIX, or ESCALATE, still counts when no
  JSON object parses. When nothing does, the result records the raw grok file
  path. Covered by `scripts/test-ir-verdict-parse.sh` (#194).

## 2026-10-31

### Changed

- The reviewer brief requires a four-field record on every review of the
  current head: agreed behaviour, the checks that ran, behaviour nobody
  asked for, and blast radius. The record is for that head only, written
  beside the PASS, FIX, or ESCALATE verdict, and it is not the should-fix
  count. A record for an older head does not count (#119).

### Fixed

- The foreman pick cap keys each in-flight entry on
  `(Target repo, issue_repo, issue)`. A branch-only entry takes `issue_repo`
  from the work order, because `factory/<issue>-*` does not carry it (#47).

## 2026-10-30

### Added

- `scripts/brief-drift-check.sh` (#51) fails CI when `agents/grok-build.md`
  documents an exit code or flag `scripts/run-work-order.sh` doesn't have, or
  when `AGENTS.md` or a brief names a `factory:*` label outside the nine
  canonical ones. It runs in the `tests` job and has fixture tests.
- `postmortems/TEMPLATE.md`, a one-page production incident template (#51).
- Foreman "Pick" step caps in-flight factory entries (open agent PRs, including
  branch-only ones) at 2 per repo, counted against the candidate issue's
  `Target repo:`; at the cap no new issue is picked (#47). The reviewer brief now
  states station 05 Review's inputs and outputs, including that an L/XL
  change goes to Scott.
- A "Run environment" section in `agents/grok-build.md` (#44) and a test
  (`grok-token-scrub` in `scripts/test-run-work-order.sh`) proving Grok Build
  is started without `GH_TOKEN` or `GITHUB_TOKEN`.

- `station-post.sh verdict` takes an optional `--should-fix N` (default
  unchanged: 1 for FIX, 0 otherwise); the reviewer brief says to pass the real
  count for FIX and ESCALATE (#47).

### Changed

- Research Scout (`agents/roles/research.md`) now files issues on research
  repos (labels `factory`, `factory:triage`, max 3 per repo per run) instead
  of opening or merging its own PRs; the factory builds them. The weekly
  summary goes to the foreman (#106).
- The foreman pick cap also counts `factory:building` issues as in flight and
  keeps scanning past a capped candidate to the next eligible one (#47).
- `AGENTS.md` section 5 no longer protects `agents/work-orders/**` (#162).
  Generated work orders are bookkeeping, so a factory PR that only adds one is
  no longer routed to `factory:blocked`. `AGENTS.md`, `agents/roles/**`,
  `agents/grok-build.md` and `CODEOWNERS` stay protected. The path list now
  lives in `scripts/protected-paths.sh`, used by `run-work-order.sh` and named
  in the reviewer brief for the `--protected` call.

### Fixed

- `station-post.sh verdict --should-fix` now matches `review-issue.sh`: no leading
  zeros, and `PASS` with a non-zero count or `FIX` with zero is rejected (#47).
- `AGENTS.md` §10.4 and the reviewer brief no longer say changes-requested
  "alone doesn't block". A bot's `CHANGES_REQUESTED` on the current head
  blocks a merge where the `factory-main` ruleset enforces the `pull_request`
  rule; verdicts must now state the observed `mergeStateStatus` (#172).

## 2026-10-29

### Added

- Monthly `Line audit` workflow and a read-only `auditor` role (#21). The
  workflow runs the role through `station-run.sh --read-only`, compares the
  scorecard with the newest `audits/*.md`, and opens a pull request with the new
  audit when it changed, listing gaps as issue candidates without filing them.
  It cannot run until a person provides the secret, variables and release tag
  named at the top of `.github/workflows/line-audit.yml`.

### Fixed

- `station-run.sh` re-execs from a private snapshot of its scripts, adapters
  and prompts, so a builder that rewrites them mid-run can no longer make the
  running bash resume at a stale offset and run a fragment (#174). The run
  says so on stderr if those files changed in the working tree, and the exit
  trap removes the snapshot, which is registered immediately so an early
  validation failure removes it too. `tree_sum` no longer ends the script
  under `set -e` when a snapshot path is absent.

- `station-run.sh` no longer deletes a writable cross-repo builder's clone on
  exit (#177). The read-only and cross-repo clones shared one variable, so the
  exit trap destroyed committed work. Now only the read-only clone is removed;
  the writable clone's path is printed as the final stdout line
  `station-run: writable-clone-path <path>`, and the reader deletes it.

### Added

- `scripts/ruleset-drift-check.sh` and a weekly `ruleset-drift.yml` workflow (#157). It
  runs the read-only `gh factory plan --json` and fails the job (exit 1) naming each
  repo whose enforced ruleset differs from `factory.yml` on `required_status_checks` or
  `bypass_actors`. The workflow needs a read-only `FACTORY_READ_TOKEN` secret that can read
  every enrolled repo, and passes `--owner adamsuk --owner touchlineHQ` explicitly. The
  output keeps four outcomes apart: confirmed drift (exit 1), rulesets `unavailable` to
  gh-factory (exit 3), `bypass_actors` that cannot be verified because GitHub shows it only
  to write access (reported, exit 0, never "matches"), and a plan with no enrolled repos
  (exit 2, since nothing was checked).
- `scripts/review-bot-metrics.sh` reports CodeRabbit review threads on recent
  closed or merged PRs per repo (total, resolved, open, acceptance rate), so
  "re-test when the model changes" has a baseline (adamsuk/software-factory#26).
  Read-only; `--repo OWNER/REPO` or `--all`, `--limit N` (default 20).
- Stations read `AGENTS.md`, the role brief and `stations/github-writes.md`
  from a promoted release tag instead of the live tree (#136).
  `FACTORY_RELEASE_REF` overrides it; the default is the latest `v*` tag
  (`v0.1.0` today), and with no tag the working tree is used. The monitor role
  reads its scripts from the same ref instead of `origin/main`. The promotion
  step is in `stations/README.md`.

- A writable `builder` on `opencode` or `claudecode` now runs in a clone of the
  repo the work order's `repo:` names when that is not this repo, so a grok
  billing halt no longer blocks every cross-repo ticket (#171). The clone keeps
  a real push URL, exports `GH_REPO`, and is removed on exit; an in-repo work
  order still runs in place. These builders still only leave edits: no commit,
  push or pull request.

- The `tests` job's failure path is verified, not assumed (#135). Every run of
  it had passed, so the branch that reports a red suite had never executed. A
  temporary `scripts/test-aaa-canary.sh` exiting 1 was added on a pull request
  and removed again; it proved three things that had been asserted and never
  observed: the job's **glob** picks up a suite that did not exist when the job
  was written, a failing suite **fails the job**, and — because the canary sorts
  first — the loop **continues past a failure**, with all twelve real suites
  still running and reporting after it. The `factory-main` ruleset reported
  `BLOCKED` while it was red, which is also the first evidence that the ruleset
  created for #112 refuses a merge. A first attempt named the canary `zzz`,
  which sorted last and so could not show the third property at all.

- A `tests` job in `.github/workflows/lint.yml` runs every `scripts/test-*.sh`
  (found by glob) on pull requests and pushes to `main`, runs all suites even
  when one fails, and lists each suite's exit status in the step summary
  (#135).
- `tests` is now in `required_checks`, so `scripts/gate-issue.sh` requires it,
  and `agents.test_command` runs `shellcheck` plus the six suites that pass on
  the factory box instead of only the linter (#135). The other six suites are
  listed in `.github/factory.yml` and tracked in #164. This tightens the
  factory's gate only; GitHub enforces nothing until a ruleset exists (#112).

### Fixed

- CI pins ShellCheck to 0.11.0 (#155). The `ShellCheck` job ran whatever
  version `ubuntu-latest` shipped, so the gate's strictness could change with no
  commit here. It now downloads the official 0.11.0 release, verifies its SHA256
  before running it, and fails on a mismatch rather than falling back to the
  image's copy. The version is set in one place in `lint.yml`; `factory.yml` and
  the README say which version is meant.
  The download is bounded (`--max-time 60`, `--retry 3`, HTTPS and TLS 1.2
  only) and the job has `timeout-minutes: 5`, so a stalled transfer fails the
  gate instead of leaving it pending.
- `scripts/test-factory-pr-metrics.sh`'s failure reporter no longer crashes on
  its own `printf` (#165). `printf '--- stdout ---\n'` makes bash parse the
  leading `---` as an option (`printf: --: invalid option`), which replaced the
  captured output it was about to print. The five section headers now use
  `printf '%s\n' '--- … ---'`. No other `scripts/test-*.sh` passes a format
  string starting with `-`. No assertion changed.

- `adapters/claudecode/run.sh` runs the `builder` role instead of refusing it
  (#158). The refusal said builder needs `scripts/run-work-order.sh`, which is
  reached only from `adapters/grok/run.sh`; `adapters/opencode/run.sh` has no
  builder case at all and runs it as a prompted agent. The premise was false, so
  the builder had one provider and no fallback — which bit on #154 when an
  opencode attempt stalled for 15 minutes and produced an identical diff. The
  model is `${FACTORY_MODEL:-sonnet}` when the Claude CLI supports `--model`,
  and the CLI's own default otherwise, since the adapter probes for the flag
  rather than requiring it; the builder is no exception either way.
- `scripts/run-work-order.sh`: make the bench clone root configurable via
  `FACTORY_WORKSPACE` (default `/workspace` unchanged), create missing roots
  if possible, fall back to a temporary directory with a loud stderr message
  naming the root and target, exit code 8 when neither root nor a temporary
  directory is usable, and write `$dir.grok.json`, `$dir.bench.txt`, `$dir.venv`
  beside the clone outside it. Documented in `stations/README.md` and
  `agents/grok-build.md`. Covered by new cases in `scripts/test-run-work-order.sh`.
- `stations/README.md` records which providers can run which roles, and that the
  grok builder clones, tests, commits, pushes and opens the pull request while
  the opencode and claudecode builders only leave edits in the tree. Calling
  both "the builder station" hid that one does a fraction of the job.

## [Unreleased]

### Added

- `scripts/wait-for-review-bot.sh`, run by `foreman-orchestrate.sh review`
  before the reviewer role, so the independent review can weigh the review
  bot's comments as AGENTS.md §10.4 requires. It had not been waiting: across
  #141, #143 and #146 CodeRabbit left 16 inline findings and no verdict read
  any of them. Satisfied by a review **or** a review comment for the exact
  commit, since neither is sufficient alone. Comments match on
  `original_commit_id`, because GitHub re-anchors a comment's `commit_id` to a
  newer commit and matching that ended the wait on heads the bot had never
  seen. The bot's check counts only when the commit is the pull request's head,
  tolerates the documented exit 8, and treats "no checks reported" as absent
  rather than fatal. Nudges `@coderabbitai full review`
  once per head per §10.2, and a timeout is not fatal. Covered by
  `scripts/test-wait-for-review-bot.sh` (15 tests).
- `scripts/factory-flagged.sh` lists the issues flagged `priority: next` on the
  Software Factory board, ordered `priority: P0`-`P3` then issue number, so
  "pick up what's flagged" resolves to one read-only command. Covered by
  `scripts/test-factory-flagged.sh`.

### Fixed

- `scripts/watcher/board-sync.sh` adds every open issue and pull request to the
  board regardless of when it was last touched. It previously only considered
  the last two days, so anything that went quiet before being added was never
  added. The `factory status` mirror keeps that window. `date -d` replaced with
  a portable form, so it no longer runs on Linux only.

## 2026-10-28

### Added

- `scripts/station-run.sh` runs the reading roles (`intake`, `research`,
  `reviewer`, `monitor`) in a throwaway clone by default rather than on request,
  so writes under the station's working directory are discarded and a plain
  `git push` fails. The clone keeps `origin`'s fetch URL so `gh` still works —
  removing it blinded the reviewer (#149) — and breaks only the push URL.
  `--writable` is the explicit way out; `foreman` and `builder` write by design.
  A station given `--repo` gets `GH_REPO`, so an unqualified `gh` read cannot
  inspect the wrong repository, and an inherited `remote.origin.pushurl` is
  refused rather than silently providing a working push target.
  It is not an OS boundary: the original checkout stays reachable by absolute
  path, which `stations/README.md` states plainly and real isolation (#44) would
  close.
- `scripts/check-test-assertions.sh` fails a pull request that changes or
  removes an existing assertion in `scripts/test-*.sh`, overridable with the
  `approved-test-change` label, and runs as the `Test assertions` CI job.
  Covered by `scripts/test-check-test-assertions.sh`.
- `adapters/claudecode/run.sh` implements the adapter interface for every
  non-builder role: the station bundle goes in on stdin in print mode and
  `AGENTS.md` is appended to the system prompt. `builder` still needs grok,
  because `scripts/run-work-order.sh` calls that CLI directly.
- `scripts/test-adapters.sh` covers the adapter contract for all three
  providers with fake CLIs on `PATH`, and CI now lints `adapters/*/run.sh`.
- [`audits/2026-10-28.md`](audits/2026-10-28.md): a Line audit scoped to this
  repo alone, against guide v2026-10-27. 27 recommendations: 2 met, 13 partial,
  12 missing. Its gaps are prioritised `P0` to `P3` under #134, one parent that
  spans all nine stations. New `priority: P0`-`P3` and `audit-2026-10-28`
  labels; #97 and #98 closed as duplicates and #15 reopened.
- `agents/work-orders/adamsuk_software-factory-138.md`: the work order that
  carries the audit through the stations, retrofitted over #138.
- `scripts/station-post.sh` posts the factory trail for any provider: one
  triage comment, one `factory:*` label, one `factory/<issue>-<slug>` pull
  request, and one PASS / FIX / ESCALATE verdict. It refuses a second triage
  comment, a second open pull request, and a merge.
- OpenCode's adapter runs `opencode run --file` (there is no `--prompt-file`)
  and the station prompt tells it to post only through that script.

### Fixed

- `.coderabbit.yaml` turns off `autofix`, `fix_ci`, `unit_tests` and
  `docstrings`. All four default to true, so CodeRabbit held standing
  permission to commit code and generate tests here, and used it: 96e5e3e
  changed an existing assertion so a test passed against an error string the
  code no longer produced. CodeRabbit now reviews and does not write.
- `adapters/opencode/run.sh` no longer passes `--dir`, which opencode v2.2.0
  rejects outright and which stopped every station on that provider. It probes
  for the flag and enters the repo root itself when it is absent.
- `adapters/grok/run.sh` separates a missing CLI from a CLI that lacks
  `--prompt-file`; both previously reported the same message.
- `scripts/gate-issue.sh` names a missing PyYAML instead of reporting
  `could not read factory.yml`, and the `gh` minimum version (2.50, for
  `gh pr checks --json`) is documented with the other prerequisites.
- `scripts/station-post.sh` treats `Closes #N` on a non-factory branch as a
  duplicate pull request, and a retry still moves the label when the comment
  was posted but the label write did not land.
- `scripts/foreman-orchestrate.sh review` requires the pull request, issue,
  repository, and head, and puts them in the reviewer prompt.
- Provider capability probes drain full help output, and OpenCode and Claude
  Code preserve caller-relative prompt paths when changing directories.
- Adapter success tests propagate failures.

## 2026-10-27 (triage retry)

### Fixed

- Triage comments record their status so retries only repair a missing label
  when the requested status matches; conflicting or unrecorded decisions are
  refused.

## 2026-10-27 (review repairs)

### Fixed

- Foreman retries allow new tests and fixture or test-data additions that
  preserve existing assertions, subject to the §5 and §10.3 restrictions.
- `scripts/review-issue.sh` accepts `PASS`, `FIX` and `ESCALATE` alongside
  legacy verdicts, preserving the existing routing and should-fix guards.

## 2026-10-27 (watcher prompt file)

### Fixed

- `scripts/watcher/watch.sh` and `scripts/watcher/watch.new.sh` pass prompts
  via `--prompt-file` so large prompts no longer exceed argument limits (#120)

## 2026-10-27 (watcher source)

### Added

- `scripts/watcher/`: factory watcher source (`watch.sh`, build-lane `watch.new.sh`, `board-sync.sh`, `swap-early.sh`, `autopush.sh`, `push-protected.sh`) with machine paths as env vars, plus `README.md` (#108)

## 2026-10-27 (pr run cost)

### Changed

- `scripts/run-work-order.sh` opens or updates the pull request on `--push`
  after `set_gate_label`, and the body includes the lines `api_equiv_usd`
  and `attempt` (#102)

## 2026-10-27

### Added

- `scripts/review-issue.sh` reads the PR Reviewer verdict on a `factory:review`
  issue and prints `merge`, `build`, `blocked`, `wait`, or `skip`. A `ready`
  verdict with no should-fix and a met review gate moves the label to
  `factory:merge`. `changes-needed` with a positive should-fix moves it to
  `factory:building` without changing `attempt`. `needs-scott` moves it to
  `factory:blocked` and comments that Scott must act (#96)
- `metrics/2026-10-26.md`: first recorded week of factory metrics for
  `adamsuk/software-factory` from 2026-10-20 through 2026-10-26 (#86)
- `.github/factory.yml` records required checks `ShellCheck` and
  `changelog / changelog` for station 04. `agents.merge` stays false (#82)

### Changed

- `AGENTS.md` §4 names `factory:gate` → `factory:review` when required checks
  are green and `factory:gate` → `factory:blocked` when the fix loop stops
  for a person, and points at §9 Status labels (#103)
- `AGENTS.md` §10 and role docs record the 27 Oct 2026 review and fix rules (#107):
  Failing CI routed to the fix path while rounds remain (otherwise blocked by failing CI),
  CodeRabbit full-review follow-up once per head commit when needed, CodeRabbit fix
  commands only on ordinary PRs with Grok Build fixes for protected/CI/tests/lockfile PRs
  (PR's own files only; reject deletes/lockfile changes/test weakening), Dependabot/lockfile-only
  PRs get no automatic fix and exhausted Grok budget waits. Independent Grok Build review
  (PASS/FIX/ESCALATE); ready only if CI green and verdict PASS on current head. CodeRabbit
  changes-requested alone doesn't block, approval alone not enough. PASS on a non-protected PR
  may merge under standing permission, PASS on a protected PR goes to Scott, FIX goes to fix
  path (3 rounds), ESCALATE goes to Scott.

### Fixed

- Declare PyYAML and document the review workflow setup so parsing factory YAML
  does not rely on an undeclared installation.

## 2026-10-26 (gate checks)

### Added

- `scripts/gate-issue.sh` reads the pull request head's required checks for a
  `factory:gate` issue and prints `review`, `retry`, `blocked`, `pending`, or
  `skip`. Green moves the label to `factory:review`. Attempt 3, a repeated red
  list, or an empty `required_checks` list moves it to `factory:blocked` and
  comments that Scott must act (#81)

### Fixed

- `scripts/gate-issue.sh` parses top-level `required_checks` as YAML, including
  blank lines, comments, quotes, flow sequences, and any legal indent. A value
  that is not a list of strings exits 7. Every `gh pr checks` row with a
  required name counts. `gh issue edit` and `gh issue comment` keep their URLs
  off stdout, including when a blocked label edit fails after the comment (#81)

## 2026-10-26

### Changed

- Foreman gate step: when a check result wakes the foreman and the issue shows
  `factory:gate`, run `scripts/gate-issue.sh` once without `--watch` and act on
  `pending`, `review`, `retry`, `blocked`, and `skip`. On `retry`, if `attempt`
  is already 3, remove `factory:gate`, add `factory:blocked`, and comment with
  the failing check names, a one-paragraph diagnosis, and that Scott must act,
  also naming the protected path if the next fix would change one. Do not
  rerun step 4. Otherwise, if the next fix would change a protected path,
  remove `factory:gate`, add `factory:blocked`, and comment that Scott must
  act, naming the path. Do not rerun step 4. Otherwise leave `factory:gate`,
  increment `attempt`, and rerun step 4 on the same branch without opening a
  second pull request. A stop while the issue shows `factory:building` removes
  `factory:building` and adds `factory:blocked`, with a comment saying why and
  who must act, so no issue is left in `factory:building` without a pull
  request. A stop while the issue shows `factory:gate` removes `factory:gate`,
  removes `factory:building` if present, and adds `factory:blocked`, with a
  comment saying why and who must act, unless this run already added
  `factory:blocked` (#83).
- Builder brief: takes only the foreman's work order for an issue already
  labelled `factory:building`, and stops after the tested commit (#80).
- Foreman step 5 copies the bench lines `attempt`, `test_command`, `tests`,
  `api_equiv_usd`, and `num_turns` unchanged into the pull request body. Before
  the PR is opened, `factory:blocked` stops the run. Otherwise Foreman removes
  `factory:building` when present, adds `factory:gate` when absent, and opens
  the PR only once that issue shows `factory:gate` without `factory:building`
  (#79)

## 2026-10-26

### Added

- `scripts/factory-pr-metrics.sh` reports read-only pull request metrics for a
  UTC window: `api_equiv_usd` cost, first-time-green, fix attempts, review
  rounds, and open pull requests whose branch starts with `factory/` (#85)

## 2026-10-26

### Added

- `agents/roles/monitor.md`: the Factory Monitor weekly brief. It runs the two
  read-only metrics scripts for `adamsuk/software-factory` and opens a pull
  request for `metrics/<last-day>.md`. The pull request script is read from
  the default branch (`origin/main`). The label script is read from
  `origin/main` when that path exists, and from `origin/factory/84-label-metrics`
  until then. A missing script commits nothing (#87)

## 2026-10-26

### Added

- `scripts/factory-label-metrics.sh`: read-only `in`, `out`, and median lead
  time for the nine `factory:*` status labels, counted from issue events (#84)

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
