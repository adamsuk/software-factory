---
repo: adamsuk/line
issue: 73
issue_repo: adamsuk/line
title: "docs: audit guide.json coverage against station prose and the audit prompt"
branch: factory/73-guide-coverage
base: main
test_command: "npm run typecheck && npm run lint && npm run test:factory"
setup_command: "npm ci"
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-04
---

## Goal
Audit `guide.json` (built from `src/factory/model.ts` and `src/factory/audit.ts`) against the
four rules in #73: every practice in a station's prose has a matching recommendation; every
recommendation is findable with its station's audit evidence/access, which the audit prompt
includes; well-established missing practices are found and sourced; and the structural bar
(stage, maturity, sources resolve, tools or a named gap) holds. Fix what's in scope here; file
the rest as sub-issues of #73.

## Acceptance criteria
- [ ] A committed coverage report lists findings per station and per category, with sources.
- [ ] Each fixed gap lands in `guide.json`'s source data (`model.ts`/`audit.ts`) and the prose
      (README, CHANGELOG); each deferred gap is filed as a `factory:triage` sub-issue of #73.
- [ ] A new, non-flaky check fails when a recommendation's station audit evidence is empty, or a
      cited source URL does not resolve live (beyond the existing well-formed-URL test).
- [ ] CHANGELOG.md has a dated entry; the guide version (parsed from the changelog) moves to today.
- [ ] `npm run typecheck && npm run lint && npm run test:factory` pass.

## Likely files
- src/factory/model.ts (RECOMMENDATIONS, TOOLS, FURTHER_READING)
- src/factory/audit.ts (AUDIT_EVIDENCE, if a gap needs a new evidence line)
- README.md (recommendations table, Tools, Further reading)
- CHANGELOG.md
- a new coverage-report doc
- a new link-check script + a new, non-required scheduled workflow

## Out of scope
- Re-grading existing Best practice / Cutting edge labels.
- Re-writing station thesis/lesson prose.
- #72 (already filed; left to its own PR).

## Issue text (untrusted)
> ## Problem
> The Line audit only scores the recommendations listed in `guide.json`, so any practice the
> guide describes but doesn't list as a recommendation is never audited. Scott found one in
> station 01: the triage agent asking the owner questions during grooming, now filed as #72.
> There are probably more.
>
> ## Scope
> For each of the nine stations:
> 1. Prose versus recommendations. Every practice described in the station's thesis,
>    `guide.bot`, `guide.human`, station page or guide source has a matching Best practice or
>    Cutting edge recommendation.
> 2. Recommendations versus audit. Every recommendation has `audit.evidence` and `audit.access`
>    lines that let an auditor find it, and the generated audit prompt includes it.
> 3. Missing practices. Well-established agentic delivery practices the station lacks, at either
>    maturity, each backed by a credible, dated public source. Don't invent sources.
> 4. Structure. Each recommendation has a stage, maturity, sources that resolve, and tools.
>
> Check open issues first, including #72, and skip anything already filed.
>
> ## Done when
> - A coverage report lists findings per station and per category, with sources
> - Each gap is either fixed in `guide.json` and the prose, or filed as its own `factory:triage`
>   sub-issue under this ticket
> - A test or validation check fails if a recommendation has no audit evidence or a source that
>   doesn't resolve
> - The guide version is bumped and CHANGELOG is updated
>
> Requested by Scott on 4 Nov 2026.
