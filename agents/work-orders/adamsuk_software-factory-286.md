---
repo: adamsuk/software-factory
issue: 286
issue_repo: adamsuk/software-factory
title: "docs: genericise operational disclosures in README and the Line audits"
branch: factory/286-publication-hardening
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-adapters.sh && bash scripts/test-check-test-assertions.sh && bash scripts/test-factory-flagged.sh && bash scripts/test-run-work-order.sh && bash scripts/test-run-work-order-llm.sh && bash scripts/test-station-run.sh && bash scripts/test-wait-for-review-bot.sh && bash scripts/test-research-brief.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-08
---

## Goal

`README.md`'s intro and the five committed Line audits (`audits/2026-10-24.md`,
`audits/2026-10-25.md`, `audits/2026-10-26.md`, `audits/2026-10-28.md`,
`audits/2026-11-03.md`) still name specific operational details that a prior,
narrower pass (#282, merged) did not reach: an analytics tool's internal
project id, a one-line database/billing architecture aside, a list of
otherwise-unnamed internal services, several GitHub ruleset/installation
numeric ids, Cloudflare deployment ids, GitHub Actions workflow-run ids, and
(in the 3 Nov audit's `per-run-credentials` row) enough mechanics of how an
installation token gets minted to read as how-it-works documentation of a
credential path rather than just the finding. Replace each with an honest,
generic descriptor and add one dated CHANGELOG entry. This is wording-only:
no date, score, sample figure, finding or stated uncertainty changes, and no
audit file is deleted or re-scored.

## Acceptance criteria

- [ ] Changed paths are exactly: `README.md`, the five files under `audits/`,
  `CHANGELOG.md`, and this work order's own
  `agents/work-orders/adamsuk_software-factory-286.md`. Nothing else,
  and nothing deleted.
- [ ] Before editing a candidate literal, `git grep` it outside `audits/`
  (and outside the `README.md` edit). If it already appears in this repo's
  own tracked, non-audit source (a script, `.github/factory.yml`,
  `scripts/watcher/README.md`), leave it exactly as written everywhere,
  including inside the audit prose it would otherwise touch.
- [ ] Every date, every scorecard count at every level (headline, per-station,
  per-recommendation), every sample size/rate, every named recommendation id,
  and every stated finding, conclusion or uncertainty in the five audits
  reads identically to the version at
  `09b9d09f1d8262de4a60dee08ad29228920df5b4`.
- [ ] The operational identifiers and mechanics described in the Goal (and any
  other instance of the same pattern found on a full re-read) are replaced by
  plain descriptive phrases — never an invented identifier dressed up to look
  real, never presented as the verbatim original value.
- [ ] The 3 Nov audit's `per-run-credentials` finding (token cached and
  reused, not minted fresh per work order) survives without the specific
  minting mechanics.
- [ ] A short, visible note states these audits' identifiers were generalised
  after the fact for publication, and that the generic wording is not a claim
  of verbatim original evidence.
- [ ] `CHANGELOG.md` gains exactly one new dated entry (`## YYYY-MM-DD`,
  Europe/London date), naming no private identifier.
- [ ] The test command above is run, under a fake `HOME` with no credential
  store reachable, and is green before handoff.
- [ ] Existing tests, CI/workflow files, lockfiles, and anything under
  `agents/roles/**`, `agents/grok-build.md`, `AGENTS.md`, or `CODEOWNERS` are
  untouched. `scripts/test-watcher-tree.sh` and the literal it checks for are
  untouched. The touchlineHQ merge-pause wording, its selector, every
  auth/merge control, and every board/project field id stay byte-for-byte as
  they are.
- [ ] PR body names the test command actually run and states, if any existing
  test file was touched, that only fixture/test data was added (it should not
  be — this PR has no reason to touch a test file at all).

## Likely files

- `README.md` — check the intro for any residual specific identifier; most
  likely only needs the redaction/historical caveat line added.
- `audits/2026-10-24.md` — the analytics-project-id mention near the scope
  paragraph; the database/billing aside in the `human-release-gate` row; the
  named-internal-services list in the unknowns section.
- `audits/2026-10-25.md` — the ruleset numeric ids introduced when the
  factory's own tooling repo and the org `.github` repo were enrolled.
- `audits/2026-10-26.md` — the analytics-project-id repeat; the Cloudflare
  production-deployment ids.
- `audits/2026-10-28.md` — re-read fresh for any residual id; none found
  beyond items already coupled to tracked scripts, but confirm rather than
  assume.
- `audits/2026-11-03.md` — the heaviest file: several ruleset/installation
  numeric ids per enrolled repo, workflow-run ids and links, and the
  `per-run-credentials` row's minting mechanics.
- `CHANGELOG.md` — one new dated entry.
- `agents/work-orders/adamsuk_software-factory-286.md` — this file,
  bookkeeping only.

## Out of scope

- Any test, CI/workflow file, lockfile, or file under `agents/roles/**`,
  `agents/grok-build.md`, `AGENTS.md`, or `CODEOWNERS`.
- `scripts/test-watcher-tree.sh` or the literal it checks for.
- Any git history rewrite, any repository-visibility change, any licence file
  (a separate, later issue once this merges).
- Any change to the touchlineHQ merge pause, its selector, any auth/merge
  control, or any board/project id.
- Discussion/comment cleanup; deleting any audit file; re-scoring any Line
  recommendation.
- Approval or merge as part of this work order — normal
  intake → ready → work order → build → gate → review flow only. This PR is
  expected to size as L/XL under the reviewer brief's own rule even though it
  is documentation-only; the reviewer should ESCALATE, not PASS-and-merge
  under standing permission, and should not be talked out of that by the
  low apparent risk of a wording change.

## Issue text (untrusted)

> Target repo: adamsuk/software-factory
>
> Goal: Make `README.md`'s introduction and the five committed Line audits
> safe to publish, by replacing specific operational disclosures with
> honest, generic descriptors, while keeping every date, scorecard count,
> sample size/rate, finding and stated uncertainty exactly as recorded.
> [...acceptance criteria, size note, out-of-scope list and publication
> caveat as posted on the issue — see the issue body itself for the full
> text; not duplicated here to avoid two copies of the same untrusted
> content.]
