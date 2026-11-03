---
repo: adamsuk/software-factory
issue: 211
issue_repo: adamsuk/software-factory
title: "docs: scope the weekly research cycle to software-factory for now, complete the PR body"
branch: factory/211-research-audit-cycle
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-sub-issues-all-closed.sh && bash scripts/test-audit-triage.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 2
created: 2026-11-03
---

## Goal

PR adamsuk/software-factory#254's independent review (ESCALATE verdict,
run on Opus) found the audit's `issues: closed` trigger only fires for
issues inside `adamsuk/software-factory` itself, so a research-cycle
parent on an actual research repo (e.g. `adamsuk/line`) never auto-starts
the audit — but `agents/roles/research.md` reads as if cross-repo already
works. Scott's decision (3 Nov 2026): ship this scoped to software-factory
only for now. The cross-repo case is tracked separately as
adamsuk/software-factory#258 — don't attempt it here.

The review's other two findings are process ones, not design ones:

1. The PR body doesn't name the exact test command run.
2. The PR body doesn't flag `.github/workflows/line-audit.yml`,
   `agents/roles/research.md` and `agents/roles/auditor.md` as protected
   paths needing Scott's review.

## What to change

1. **`agents/roles/research.md`**: reword the parent/sub-issue section so
   it's explicit that the automatic "closing the last sub-issue starts the
   audit" trigger currently works **only when the research-cycle parent
   lives in `adamsuk/software-factory` itself**. For a parent on any other
   enrolled repo, starting the audit today needs a manual
   `workflow_dispatch` with `parent_repo`/`parent_issue` — reference
   adamsuk/software-factory#258 as the tracked follow-up for making that
   automatic everywhere. Don't change any code — this is a wording-accuracy
   fix only.
2. **PR body** (next review reads the live PR, not a new comment — update
   it via whatever mechanism `scripts/run-work-order.sh`/the foreman
   normally uses to refresh a PR body, or note in the report if this build
   path can't edit the PR body itself and it needs doing at the `--push`
   step): state the exact test command from this work order's frontmatter,
   and list the three protected files above explicitly, asking for Scott's
   review regardless of verdict.

## Out of scope

- Any code change to `.github/workflows/line-audit.yml`,
  `scripts/sub-issues-all-closed.sh`, or `scripts/audit-triage.sh` — all
  already correct and tested in round 1.
- The cross-repo wiring itself — that's adamsuk/software-factory#258,
  explicitly deferred by Scott.

## Acceptance criteria

- [ ] `research.md` states plainly that automatic cross-repo triggering
      isn't built yet, names the current manual workaround, and references
      adamsuk/software-factory#258
- [ ] The PR body names the test command and the three protected paths
- [ ] `shellcheck scripts/*.sh adapters/*/run.sh && bash
      scripts/test-sub-issues-all-closed.sh && bash
      scripts/test-audit-triage.sh` still passes
- [ ] `CHANGELOG.md` gets a short line noting the scoping clarification (or
      amend the existing #211 entry, your call — say which)

## Constraints

- `agents/roles/research.md` is protected (AGENTS.md §5, `agents/**`).

## Report back

Confirm the exact wording added to research.md, and whether the PR body
was updated directly by this build step or still needs the push/foreman
step to do it.
