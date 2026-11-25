---
repo: adamsuk/viva-skills
issue: 497
issue_repo: adamsuk/software-factory
title: "viva 0.6.2: practice mode over past merged PRs (experiment 1); viva-assess 0.4.1"
branch: factory/497-practice-mode
base: main
test_command: "bash scripts/test-validate-skills.sh && bash scripts/validate-skills.sh && bash scripts/test-check-log-contract.sh && bash scripts/test-hook.sh"
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-25
---

## Goal
Add `/viva practice [N]` to the viva skill: one question per past merged PR of the user's own, with a think/recall rating kept in `~/.agents/viva-experiment.md`, and let `viva-assess` summarise it. This is the skill half of #497 (platform half: adamsuk/viva#23).

## Acceptance criteria
- [ ] `viva` scope h (Practice) lists the user's merged PRs newest first, skips ones already logged or in the experiment file, and takes up to N (default 5) one at a time
- [ ] Each practice PR is logged with scope `practice`; the log line format is unchanged
- [ ] After each reveal the think/recall/mixed/skip answer is appended to `~/.agents/viva-experiment.md`, never rewriting lines, and "no log" skips it
- [ ] `viva-assess` summarises the experiment file with progress toward 20
- [ ] Patch bumps (`viva` 0.6.2, `viva-assess` 0.4.1), README, changelog; validator and contract check pass

## Out of scope
- Any log field or schema version change
