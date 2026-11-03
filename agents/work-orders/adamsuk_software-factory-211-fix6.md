---
repo: adamsuk/software-factory
issue: 211
issue_repo: adamsuk/software-factory
title: "fix: close an empty-parent gap, a candidate-format gap, and a matcher-answer tolerance gap"
branch: factory/211-research-audit-cycle
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-audit-triage.sh && bash scripts/test-check-candidate-size.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 6
created: 2026-11-03
---

## Goal

CodeRabbit's review of PR adamsuk/software-factory#254's round-5 fix found
four more real gaps. Fix all four:

1. **An empty research-cycle parent can get stuck open.**
   `agents/roles/research.md` step 2 says "Skip the parent only when step 1
   found nothing" — but if step 1 finds changes that *all* already have
   open issues, step 3 files zero new sub-issues anyway, and a parent with
   zero sub-issues still gets created. `scripts/sub-issues-all-closed.sh`
   already treats a parent with no sub-issues at all as an error (exit 2,
   "nothing to review"), so that parent can never be detected as
   auto-closeable.
2. **A candidate title in a format the parser doesn't recognize is
   silently dropped.** `scripts/audit-triage.sh`'s `awk` splitter only
   starts a new candidate on a line beginning `- `, `* `, a numbered
   `N. `, or `### `. `agents/roles/auditor.md`'s step 4 ("print `##
   Candidate issues`... each with a one-line title") never specifies
   which of those forms to use. A title like `1) Enable push protection`
   (parenthesis instead of period) produces **zero** candidate files, and
   `audit-triage.sh` then reports no findings and closes the parent as if
   triage were complete — even though real candidates existed.
3. **The matcher's `MATCH <number>` answer is rejected if it includes a
   `#`.** The regex in `scripts/audit-triage.sh` is
   `^MATCH\ ([1-9][0-9]*)$`, so `MATCH #41` (a plausible answer, since
   GitHub issue numbers are conventionally written with `#`) falls through
   to the `NEW` fallback, and triage can file a duplicate for an issue
   that already covers the candidate (bounded by the existing 5-per-run
   cap, but still a real loss of accuracy).
4. **This work order's own `attempt: 5` version of itself had an
   incomplete `test_command`** — the round-5 fix order's `test_command`
   never ran `scripts/test-check-candidate-size.sh`, the new test it
   asked for. (This is a historical-record nit on
   `agents/work-orders/adamsuk_software-factory-211-fix5.md` with zero
   behavioural effect — the test was in fact run and verified by hand both
   times. Fix it anyway, briefly, for an accurate record; don't spend more
   than a one-line edit on it.)

## What to change

1. **`agents/roles/research.md`**: change step 2's skip condition from
   "Skip the parent only when step 1 found nothing" to skip whenever step
   3 will file **zero new sub-issues** — whether because step 1 found
   nothing, or because every change it found already has an open issue.
2. **`agents/roles/auditor.md`**: in step 4, specify explicitly that each
   candidate's one-line title must start with one of `- `, `* `, a
   numbered `N. `, or `### ` — the exact forms
   `scripts/audit-triage.sh`'s parser recognizes.
3. **`scripts/audit-triage.sh`**: after splitting candidates, if the
   `## Candidate issues` section it was given is non-empty (the
   `--candidates` file has content) but the split produced **zero**
   candidate files, treat that as an error (`die 7` or similar) rather
   than silently proceeding to "no findings, close the parent."
4. Accept an optional `#` in the matcher's `MATCH` answer:
   ```diff
   -    elif [[ $last =~ ^MATCH\ ([1-9][0-9]*)$ ]] \
   +    elif [[ $last =~ ^MATCH\ #?([1-9][0-9]*)$ ]] \
   ```
   Keep the existing `NEW` fallback for every other unusable answer, and
   keep the grep-against-open-list check unchanged.
5. **`agents/work-orders/adamsuk_software-factory-211-fix5.md`**: add
   `&& bash scripts/test-check-candidate-size.sh` to its `test_command`
   line. One-line fix, nothing else in that file changes.

## New/updated tests needed

- A case proving a non-empty candidates section that parses into zero
  candidate files is rejected by `audit-triage.sh` (not silently treated
  as "no findings").
- A case proving `MATCH #<n>` (with the `#`) is accepted the same as
  `MATCH <n>`, and that other unusable answers still fall back to `NEW`
  (don't weaken `scripts/test-audit-triage.sh:94-96`'s existing assertion
  for that).
- For research.md's step-2 wording: this is a role-brief prose change,
  not executable code — trace it by hand in the report rather than
  inventing a test that can't actually exercise an LLM-followed
  instruction. Say so plainly.

## Out of scope

- Everything already deferred: #266, #267, #258, the declined
  secret-masking and over-redaction findings.
- Any other wording change to `research.md` or `auditor.md` beyond the
  two specific gaps above.

## Acceptance criteria

- [ ] `research.md` step 2 skips the parent whenever step 3 would file
      zero new sub-issues, not just when step 1 found nothing
- [ ] `auditor.md` step 4 specifies the exact accepted title-prefix forms
- [ ] `audit-triage.sh` rejects a non-empty candidates section that
      parses into zero candidates, with a new test proving it
- [ ] `audit-triage.sh` accepts `MATCH #<n>` as well as `MATCH <n>`, with
      a new test proving it, and the existing `NEW`-fallback assertion is
      unchanged
- [ ] The round-5 work order's `test_command` includes
      `test-check-candidate-size.sh`
- [ ] `shellcheck scripts/*.sh adapters/*/run.sh` stays clean
- [ ] `CHANGELOG.md` gets a line for this round

## Constraints

- `agents/roles/research.md` and `agents/roles/auditor.md` are protected
  paths (AGENTS.md §5, `agents/**`).
- Don't touch anything already deferred to #266, #267, or #258.
- Don't weaken any existing test assertion — only add new ones.

## Report back

For the two code fixes (zero-candidate rejection, MATCH # tolerance), show
the new tests failing against pre-fix code and passing after. For the two
role-brief wording fixes, trace by hand why the new wording closes the gap
and say so plainly rather than claiming a test exists where none can.
