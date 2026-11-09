# Role: monitor (Factory Monitor)

Runs once a week. Follows [AGENTS.md](../../AGENTS.md). The maintainer creates the
Grok Bot teammate. This file is the procedure. It does not grant permission to merge.

## Inputs

- `scripts/factory-label-metrics.sh`, `scripts/factory-pr-metrics.sh`,
  `scripts/factory-delivery-metrics.sh`, and `scripts/review-bot-metrics.sh`.
  All four are read-only. Read each one from the promoted release ref (`$REF`)
  only. All four are already on `main`.
- One repository in this first version: `$FACTORY_HOME_REPO`.
- The ledger path is `$FACTORY_LEDGER_FILE`, defaulting to `$FACTORY_HOME/factory-ledger.csv`, where `$FACTORY_HOME` defaults to `${XDG_DATA_HOME:-$HOME/.local/share}/software-factory` (see `scripts/watcher/README.md`).

The weekly procedure stays inactive until all four scripts can be read from
`$REF`. If any of the four paths is missing on `$REF`, commit nothing and
report the missing path to the maintainer.

## Steps

0. **Ref.** `REF` is `$FACTORY_RELEASE_REF` if set, else the latest tag
   matching `v*` (`git tag --list 'v*' --sort=-v:refname | head -n 1`).
1. **Window.** Take the date in UTC. `until` is the next UTC date, `YYYY-MM-DD`.
   `since` is seven days before `until`. The last day included is the day
   before `until`.
2. **Measure.** For each of `scripts/factory-label-metrics.sh`,
   `scripts/factory-pr-metrics.sh`, and `scripts/factory-delivery-metrics.sh`,
   run `git show "$REF:<path>"`. Write each script to a temporary file, run
   `bash` on that file, and delete the temporary file. Pass
   `--repo "$FACTORY_HOME_REPO" --since <since> --until <until>` to each of
   those three.
   For `scripts/factory-delivery-metrics.sh` also pass `--ledger` from
   `$FACTORY_LEDGER_FILE` (see Inputs) and one `--required-check` each for `ShellCheck`, `changelog / changelog`,
   and `tests`. Then run `scripts/review-bot-metrics.sh --repo "$FACTORY_HOME_REPO"`
   the same way (it takes no `--since` or `--until`; pass neither). If any path is missing on `$REF`, or any script exits
   non-zero, commit nothing and report the missing path or the failure to
   the maintainer.
3. **Record.** Write `metrics/<last-day>.md`: the label script's stdout, one
   blank line, then the pull request script's stdout, one blank line, then
   the delivery script's stdout, one blank line, then the review-bot script's
   stdout (`scripts/review-bot-metrics.sh`, CodeRabbit comment acceptance).
   Change no other file. Open a pull request
   whose body contains that file's path. Do not merge the pull request.
4. **Stop.** Do not set `factory:done`. Do not add or edit a file under
   `.github/workflows/`. Do not call PostHog. Do not file an alert. Do not
   pass another repository to the scripts. Do not commit any file other than
   `metrics/<last-day>.md`.

## Out of scope

Harness evals. `factory:done` is set by 09 Return (AGENTS.md section 9), not
by this role.
