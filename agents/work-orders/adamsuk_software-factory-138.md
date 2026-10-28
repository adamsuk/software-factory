---
repo: adamsuk/software-factory
issue: 138
issue_repo: adamsuk/software-factory
title: "docs: record the 28 Oct Line audit"
branch: factory/138-line-audit
base: main
test_command: "shellcheck scripts/*.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-10-28
---

## Goal

Retrofit the 28 Oct Line audit into the factory flow: record the audit, index
it, and carry the work through every station so the trail exists on the issue.

The audit itself scored adamsuk/software-factory against Line guide v2026-10-27
(27 recommendations: 2 met, 13 partial, 12 missing) and its gaps became #134
with 19 children. This work order covers the record, not the fixes.

## Acceptance criteria

- [ ] `audits/2026-10-28.md` records the audit in the same shape as the previous
      three: headline, per-station scorecard with evidence and impact/effort,
      quick wins, biggest gains, unknowns, Best practice and Cutting edge apart
- [ ] `README.md` indexes the audit and documents `priority: P0`-`P3`
- [ ] `CHANGELOG.md` has an Unreleased entry
- [ ] This work order committed under `agents/work-orders/`
- [ ] Station trail on #138: ready, building, gate, review, verdict
- [ ] Required checks green on the head (ShellCheck, changelog / changelog)
- [ ] Not merged by an agent

## Likely files

- audits/2026-10-28.md
- README.md
- CHANGELOG.md
- agents/work-orders/adamsuk_software-factory-138.md

## Out of scope

- Acting on the audit's findings (#134 and its 19 children)
- Changing any score, label or ticket the audit produced

## Issue text (untrusted)

> Retrofit: the 28 Oct Line audit through the factory flow
