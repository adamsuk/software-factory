---
repo: adamsuk/software-factory
issue: 211
issue_repo: adamsuk/software-factory
title: "fix: fail loud on a truncated candidate list, paginate past 200 open issues"
branch: factory/211-research-audit-cycle
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-audit-triage.sh && bash scripts/test-sub-issues-all-closed.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 4
created: 2026-11-03
---

## Goal

CodeRabbit's review of PR adamsuk/software-factory#254 found two real,
cheap-to-fix gaps. Two other findings from the same round (a concurrency
race between `audit` and `triage`, and a per-candidate dedup gap in
`audit-triage.sh`) are deferred to #266 and #267 — **do not** fix those
here, they're out of scope for this round. A third finding (cross-repo
token) is the same root cause as #258, already deferred — also out of
scope. A fourth (GitHub secret-masking on the candidates output) was
declined outright as not a real risk — also out of scope.

**This round fixes only:**

1. **Silent truncation of an oversized candidate list.** In
   `.github/workflows/line-audit.yml`'s "Export the candidates for triage"
   step, `head -c 60000 "$RUNNER_TEMP/candidates.md"` silently drops
   anything past 60,000 bytes. The `triage` job then runs on the truncated
   file as if it saw every candidate, and closes the parent as though
   triage were complete — even though some candidates were silently
   dropped.
2. **No pagination past 200 open issues.** In `scripts/audit-triage.sh`,
   `gh issue list --repo "$repo" --label factory --state open --limit 200`
   caps at 200 results with no `--paginate`. A repo with more than 200
   open `factory`-labelled issues could have a real matching issue missing
   from `open_list`, so the matcher can never select it, and a duplicate
   gets filed instead of a comment on the existing issue.

## What to change

1. In `.github/workflows/line-audit.yml`, before (or instead of) the
   `head -c 60000` truncation: check whether `candidates.md` exceeds that
   size, and if so, fail the audit job with a clear `::error::` message
   rather than silently truncating and proceeding. (Raising the limit is
   not the fix being asked for — failing loud is.)
2. In `scripts/audit-triage.sh`, add `--paginate` to the `gh issue list`
   call (and drop or raise `--limit 200` as appropriate for pagination —
   check `gh issue list --help` for how `--paginate` interacts with
   `--limit`, since `--limit` may need to be dropped or raised for
   `--paginate` to actually fetch everything).

## New/updated tests needed

- In an existing or new test file, a fixture candidates file larger than
  60,000 bytes causes the audit workflow's export step to fail rather than
  silently truncate. (If this step genuinely can't be unit-tested outside
  the real workflow runner, say so plainly and show the logic traced by
  hand instead — don't fake a test that doesn't actually exercise the
  `head -c` boundary.)
- In `scripts/test-audit-triage.sh`, a fixture with a fake `gh issue list`
  returning more than one page of results (if the existing fake-`gh`
  harness can simulate pagination) proving a match beyond the first 200
  is still found. If genuinely impractical to simulate, say so and show
  by hand that `--paginate` is passed to the real call.

## Out of scope

- The concurrency race (#266), the per-candidate dedup gap (#267), the
  cross-repo token gap (#258), and the declined secret-masking finding —
  none of those are touched in this round.
- Raising the 60,000-byte limit itself — this round only makes exceeding
  it a loud failure instead of a silent truncation.

## Acceptance criteria

- [ ] A candidates file over 60,000 bytes fails the audit loudly, rather
      than silently truncating
- [ ] `scripts/audit-triage.sh`'s issue lookup paginates past 200 results
- [ ] All existing `test-audit-triage.sh` and `test-sub-issues-all-closed.sh`
      cases still pass
- [ ] `shellcheck scripts/*.sh adapters/*/run.sh` stays clean
- [ ] `CHANGELOG.md` gets a line for this round

## Constraints

- `.github/workflows/line-audit.yml` is a protected path (AGENTS.md §5),
  already true of this PR.
- Don't touch anything already deferred to #266, #267, or #258.

## Report back

For each fix, state plainly whether it was tested with a real fixture or
traced by hand, and why.
