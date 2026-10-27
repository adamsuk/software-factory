---
repo: adamsuk/gh-factory
issue: 15
issue_repo: adamsuk/software-factory
title: "Scale review depth to PR size and risk"
branch: factory/15-scale-review-depth
base: main
test_command: "shellcheck scripts/*.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: none
attempt: 1
created: 2026-10-27
---

## Goal

Scale review depth to PR size and risk by shipping a size-label workflow as a gh-factory baseline file and writing depth rules (large diffs and protected paths go to Scott). Land in adamsuk/gh-factory. Keep PRs small/split when needed.

## Acceptance criteria

- [ ] A size-label workflow ships as a gh-factory baseline file (SHA-pinned)
- [ ] Written review-depth rules by size and risk (e.g. billing, auth and migrations always get a deep review; large diffs and protected paths go to Scott)
- [ ] Issue Shipper/foreman guidance updated to keep PRs small or split them (if applicable)
- [ ] Tests/verification as appropriate for workflow changes

## Likely files

- .github/workflows/size-label.yml (baseline in gh-factory)
- README/docs in gh-factory about review depth
- Possibly factory baseline templates

## Out of scope

- Open-PR cap (#98) and required approvals (#9) remain separate
- Other repos beyond gh-factory baseline distribution

## Issue text (untrusted)

> Target repo: adamsuk/gh-factory
> 
> From the Line audit of 2026-10-25: [audits/2026-10-25.md](https://github.com/adamsuk/software-factory/blob/main/audits/2026-10-25.md).
> 
> ### Line recommendation
> - **`scale-review`** (05 Review, Best practice): Keep PRs small. Scale how deeply a person reviews to the size and risk of the change.
>   - Current score: **partial**. No size labels or depth rules.
> 
> **Target repo(s):** all enrolled repos (via the gh-factory baseline)
> 
> ### Done when
> - [ ] A size-label workflow ships as a gh-factory baseline file (SHA-pinned)
> - [ ] Written review-depth rules by size and risk (e.g. billing, auth and migrations always get a deep review)
> - [ ] Issue Shipper is told to keep PRs small, or split them
> 
> **Impact and effort:** Impact M, effort M. Biggest gain 5.
> 
> **Delivery:** **gh-factory:** yes, a new baseline workflow. The rules are manual.
> 
> ## Line audit 2026-10-27
> **Score:** partial. Best practice. Impact M, effort M.
> **Evidence:** The reviewer cost-mode says to scale depth to size and risk. No size labels and no depth rule in the gate. Recent large merges include software-factory #93 (+1376/−0, 3 files), software-factory #101 (+1362/−0, 5 files), line #42 (+907/−7, 9 files) and activity-feed #1 (+1102/−223, 14 files). Open line #55 was +849/−871 at audit time. #47 is still open.
> **Remaining gap:** Ship the size-label workflow as a gh-factory baseline file, and write the depth rule (large diffs and protected paths go to Scott). Land the workflow in adamsuk/gh-factory. The open-PR cap stays on #98. Required approvals stay on #9.
