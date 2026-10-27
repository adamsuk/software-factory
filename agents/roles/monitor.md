# Role: monitor (Factory Monitor)

Runs once a week. Follows [AGENTS.md](../../AGENTS.md). Scott creates the Grok
Bot teammate. This file is the procedure. It does not grant permission to merge.

## Inputs

- `scripts/factory-label-metrics.sh` and `scripts/factory-pr-metrics.sh`. Both
  are read-only. Read each one from the default branch (`origin/main`) when
  that path exists there. Otherwise read `scripts/factory-label-metrics.sh`
  from `origin/factory/84-label-metrics`. Do not read
  `scripts/factory-pr-metrics.sh` from any other ref.
- One repository in this first version: `adamsuk/software-factory`.

The weekly procedure stays inactive until both scripts can be read from those
refs. If either path is missing, commit nothing and report the missing path
to Scott.

## Steps

1. **Window.** Take the date in UTC. `until` is the next UTC date, `YYYY-MM-DD`.
   `since` is seven days before `until`. The last day included is the day
   before `until`.
2. **Measure.** For `scripts/factory-pr-metrics.sh`, run `git show
   origin/main:scripts/factory-pr-metrics.sh`. For
   `scripts/factory-label-metrics.sh`, use that same `origin/main` path when
   it exists, and otherwise `git show
   origin/factory/84-label-metrics:scripts/factory-label-metrics.sh`.
   Write each script to a temporary file, run `bash` on that file with
   `--repo adamsuk/software-factory --since <since> --until <until>`, and
   delete the temporary file. If either script cannot be read, or either
   exits non-zero, commit nothing and report that to Scott.
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
