# Role: monitor (Factory Monitor)

Runs once a week. Follows [AGENTS.md](../../AGENTS.md). Scott creates the Grok
Bot teammate. This file is the procedure. It does not grant permission to merge.

## Inputs

- `scripts/factory-label-metrics.sh` and `scripts/factory-pr-metrics.sh` on the
  default branch. Both are read-only.
- One repository in this first version: `adamsuk/software-factory`.

## Steps

1. **Window.** Take the date in UTC. `until` is the next UTC date, `YYYY-MM-DD`.
   `since` is seven days before `until`. The last day included is the day
   before `until`.
2. **Measure.** Run each script with
   `--repo adamsuk/software-factory --since <since> --until <until>`.
   If either exits non-zero, commit nothing and report the exit code to Scott.
3. **Record.** Write `metrics/<last-day>.md`: the label script's stdout, one
   blank line, then the pull request script's stdout. Change no other file.
   Open a pull request whose body contains that file's path. Do not merge the
   pull request.
4. **Stop.** Do not set `factory:done`. Do not add or edit a file under
   `.github/workflows/`. Do not call PostHog. Do not file an alert. Do not
   pass another repository to the scripts.

## Out of scope

Change failure rate, recovery time, rework, and harness evals. `factory:done`
is set by 09 Return (AGENTS.md section 9), not by this role.
