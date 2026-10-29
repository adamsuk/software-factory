---
repo: adamsuk/software-factory
issue: 21
issue_repo: adamsuk/software-factory
title: "feat: schedule a monthly Line re-audit"
branch: factory/21-monthly-audit
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-station-run.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-10-29
---

## Goal

Four audits exist (`audits/2026-10-24.md` through `2026-10-28.md`), all
produced manually: a person asked an agent to score the repo against the
Line guide, and a separate work order (e.g. #138) retrofitted the record
afterward. Nothing is scheduled. This ticket automates the recurring part.

Read the four existing audit files first to understand their shape
(scorecard, evidence, impact/effort, quick wins, biggest gains, unknowns) —
whatever this produces must match that shape, not invent a new one.

## What to build

1. A new read-only role, `agents/roles/auditor.md`, modeled on the existing
   roles in `agents/roles/` (read their conventions — frontmatter-less or
   not, how they're structured, how they cite AGENTS.md). Its job: read the
   Line guide (linked from the existing audit files) and the current repo
   state, and produce an audit in the same shape as the existing ones.
2. A scheduled GitHub Actions workflow (monthly cron) that:
   - Runs `scripts/station-run.sh --read-only --provider <default>
     auditor <context>` (or the equivalent invocation — check
     `station-run.sh`'s actual interface, don't guess)
   - Diffs the result against the most recent file under `audits/`
   - Opens a PR adding `audits/YYYY-MM-DD.md` if there's a new audit to
     record
   - Proposes new gaps as draft issues or as a list in the PR body —
     **do not auto-create issues for every gap**; the issue says "Scott
     decides which become work", so surface candidates, don't file them
3. Document, in the workflow file or `stations/README.md`, which secrets
   or access this requires that a builder cannot provision (an API key for
   whichever provider runs the auditor role, any additional scopes). List
   them explicitly rather than guessing a value or leaving the workflow
   silently broken.

## Out of scope (do not do these in this attempt)

- Actually running the schedule end-to-end this attempt — if the needed
  secret doesn't exist, that's expected; name it and stop there, same as
  any other missing credential. Don't invent one or skip the check
- `admin:org` access, Cloudflare Pages access, or anything the existing
  audits already listed as "unknowns needing more access" — list them
  again if still true, don't attempt to acquire them
- Auto-filing issues for every gap found — draft/propose only
- Changing the Line guide itself or past audit files

## Acceptance criteria

- [ ] `agents/roles/auditor.md` exists and follows the existing roles'
      conventions
- [ ] A monthly-cron workflow exists, wired to run the auditor role
      read-only through `station-run.sh`
- [ ] It diffs against the latest `audits/*.md` and opens a PR with the new
      file when there's something to record
- [ ] It proposes gaps as issue candidates without auto-filing them
- [ ] Any missing secret/credential needed for this to actually run is
      named explicitly (in the workflow file as a comment, or in the PR
      body) — not worked around
- [ ] `shellcheck scripts/*.sh adapters/*/run.sh` and
      `bash scripts/test-station-run.sh` pass unmodified except additions
- [ ] `CHANGELOG.md` gains a dated entry

## Constraints

- `agents/**` is protected under AGENTS.md §5 (agent instructions) — adding
  a new role file is a new file, not an edit to an existing one, but say so
  in the PR anyway and ask for Scott's review since this is a judgment call
- `.github/workflows/**` is also protected (CI config) — same, flag it
- If, partway through, you find this needs a decision only Scott can make
  (which provider/model runs the auditor role and at what cost, whether a
  new role file is the right shape at all, etc.) — stop, say so clearly,
  and don't guess. A partial, honest escalation is a better outcome than a
  workflow that silently can't run
