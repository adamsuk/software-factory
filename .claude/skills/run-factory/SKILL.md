---
name: run-factory
description: Step one software-factory backlog ticket through its defined stations (intake, foreman pick/build, gate, review) end to end, narrating what's running and why, and pausing only for genuine human decisions — a protected-path change, a FIX that needs judgment, an ESCALATE, or anything merge/approve-shaped — using multiple-choice questions instead of open-ended ones. Use this whenever the user wants to "run a ticket through the factory," "pick up the next ticket," "work on a specific issue by number," or otherwise asks to move a software-factory backlog item forward, including when they don't name a specific station but clearly mean "make progress on the backlog using the real pipeline." Trigger this instead of manually running scripts/station-run.sh, scripts/gate-issue.sh, scripts/foreman-orchestrate.sh etc. one at a time from scratch, and instead of re-deriving AGENTS.md/stations/README.md's rules from first principles — this skill already encodes the mechanics, the known gotchas, and where a person (not an agent) must decide.
---

# Running a ticket through the factory

The actual playbook lives in **`stations/run-factory.md`** (with
**`stations/run-factory-quirks.md`** alongside it), not here — it's written
to be followed by any agent operating this repo, or by a person doing the
same steps by hand, not just a Claude Code session. Keeping one copy there
means a `grok` or `opencode` run (or a human) gets the same accumulated
knowledge as a Claude Code run, instead of it being locked behind this
skill's own loading mechanism.

**Read `stations/run-factory.md` now, in full, and follow it exactly.**
Wherever it says to stop and offer the person running it concrete,
mutually exclusive options, use the `AskUserQuestion` tool for that (that's
the "structured multiple-choice prompt" it refers to in this environment).
Everything else in it — which script to run at each step, how to interpret
each one's output, the decision-point table, the known gotchas — applies
as written.
