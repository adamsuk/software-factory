# Factory watcher

Source for the two factory watcher lanes. The scripts read their machine paths and owner settings from environment variables. Each value below is the committed default, so the scripts run on any machine and for any owner. State files, budget contents, ledger contents, and `webhook.curl` are not committed.

## Environment

| Variable | Committed default |
| --- | --- |
| `FACTORY_HOME` | `${XDG_DATA_HOME:-$HOME/.local/share}/software-factory` |
| `FACTORY_WATCH_ROOT` | `$FACTORY_HOME/factory-watch` |
| `FACTORY_BUDGET_FILE` | `$FACTORY_HOME/factory-budget.json` |
| `FACTORY_LEDGER_FILE` | `$FACTORY_HOME/factory-ledger.csv` |
| `FACTORY_CLONE_ROOT` | `$FACTORY_HOME` |
| `FACTORY_WORKSPACE` | `$FACTORY_HOME` |
| `FACTORY_HOME_REPO` | `$GITHUB_REPOSITORY`, then the `origin` remote of the current checkout, then `gh repo view` |
| `FACTORY_REPOS` | `$FACTORY_HOME_REPO` |
| `FACTORY_APPROVER_LOGIN` | the owner part of `FACTORY_HOME_REPO` |
| `FACTORY_BLOCKED_OWNERS` | empty (no owner blocked) |
| `LANE` | `main` |

`FACTORY_HOME` is the base every path derives from: set it to a directory D and the watcher uses `D/factory-watch`, `D/factory-budget.json`, `D/factory-ledger.csv`, and clone root `D`. `FACTORY_WATCH_ROOT` is the script root: `cd`, logs, `state/`, orders, `webhook.curl`, heartbeat, status, needs-scott, and `PAUSE`. `FACTORY_BUDGET_FILE` and `FACTORY_LEDGER_FILE` are the budget and ledger paths. `FACTORY_CLONE_ROOT` is the parent of the `wo-<owner>_<repo>-<issue>-*` build clones that `push-protected.sh` pushes.

`FACTORY_HOME_REPO` (`owner/repo`) holds work orders and epics: the watcher clones it, plans its epics, and matches focus and close references against it. The watcher usually runs from `FACTORY_WATCH_ROOT`, which is not a clone, so set `FACTORY_HOME_REPO` on the host. `FACTORY_REPOS` is the space-separated `owner/repo` allowlist the lanes work on. `FACTORY_APPROVER_LOGIN` is the human login whose comments count as approval: `push-protected.sh` accepts its comment containing `<!-- factory:approve -->` (or the legacy chat-approval marker). `FACTORY_BLOCKED_OWNERS` is a space-separated list of owners the watcher never clones, modifies or merges, and the prompts name that list; there is no default list in code. `LANE` stays as it is in the lane scripts. The committed default is `main`.

Each watcher script inlines the same short block between `# >>> factory env` and `# <<< factory env`, so no script sources another file.

## Lanes

Both lanes are long-running bash processes. Each cycle ends with a 180-second cycle sleep (`sleep 180`).

- Main lane, `watch.sh`. No `LANE` override (committed default `main`). Lock `watch.lock`. Log `watch.log`.
- Build lane, `watch.new.sh`. `LANE=build`. Lock `watch-build.lock`. Log `watch-build.log`.

On the CodeRabbit resume path, the main lane skips a head that already has a review before the pause check. The build lane does that skip only when the lane is not paused. In the main loop, the main lane always calls `step_build`. The build lane calls `step_build` only when `build_lane_alive` is false. No script sources another file.

## State files

State files live under `$FACTORY_WATCH_ROOT/state/` and are not committed. That directory holds per-PR markers, grok output, `events-pending.txt`, `events-sent.log`, `cr-requests.log`, `plan-count-YYYY-MM-DD`, and the flock files `append.lock`, `events.lock`, and `build-claim.lock`.

`webhook.curl` is a curl config in `$FACTORY_WATCH_ROOT`. The watcher never prints it. Without that file, digest lines stay pending.

## Budget file

The budget file is JSON at `FACTORY_BUDGET_FILE`. The watcher reads `max_grok_build_runs_per_week`, `max_grok_build_runs_per_day`, `max_runs_per_loop`, `max_coderabbit_requests_per_hour`, and `merge_protected_issues`. Budget contents are not committed.

## Ledger

The ledger is a CSV at `FACTORY_LEDGER_FILE` with header `date_utc,kind,repo,issue_or_pr,grok_sessions,api_equiv_usd,result`. Ledger contents are not committed.

## Swapping a script safely

`swap-early.sh` is the safe swap. For one lane it waits until that lane's log ends on the cycle sleep, stops that lane, clears its lock holder, copies the live script aside, moves the staged script (the live name with `.early`) into place, and starts it again. The build lane starts with `LANE=build`. The main lane starts with an empty environment list. Run it from `$FACTORY_WATCH_ROOT` after placing the staged script next to the live one.

The lane scripts fence untrusted prompt text with `fence-untrusted.sh` (AGENTS.md section 1). They find it beside the live script, at `../fence-untrusted.sh` when run from a checkout, or in the fresh home-repo main clone `step_triage` already makes. A flat `FACTORY_WATCH_ROOT` deployment therefore needs a copy beside the live scripts for `write_untrusted_block` callers (review, plan, build); without one they keep the older escaped fixed fence, while triage still uses the clone's helper or writes no prompt at all (it fails closed).

## Board settings

`board-sync.sh` copies factory labels onto a GitHub project board. The board is configuration, not committed constants. Set all five, or the script prints `board sync not configured` and exits 0:

| Variable | Meaning |
| --- | --- |
| `FACTORY_BOARD_OWNER` | project owner login |
| `FACTORY_BOARD_NUMBER` | project number |
| `FACTORY_BOARD_PROJECT_ID` | project node id |
| `FACTORY_BOARD_FIELD_ID` | node id of the `factory status` single-select field |
| `FACTORY_BOARD_OPTIONS` | JSON object mapping each status name (`Triage`, `Ready`, `Building`, `Gate`, `Review`, `Merge`, `Release`, `Blocked`, `Done`) to its option id |

It syncs the repos in `FACTORY_REPOS`. `board-sync.sh --once` runs one sync and exits.
