# Factory watcher

Source for the two factory watcher lanes. The scripts commit their machine paths as environment variables. Each value below is a committed default. State files, budget contents, ledger contents, and `webhook.curl` are not committed.

## Environment

| Variable | Committed default |
| --- | --- |
| `FACTORY_WATCH_ROOT` | `/workspace/factory-watch` |
| `FACTORY_BUDGET_FILE` | `/workspace/factory-budget.json` |
| `FACTORY_LEDGER_FILE` | `/workspace/factory-ledger.csv` |
| `FACTORY_CLONE_ROOT` | `/workspace` |
| `LANE` | `main` |

`FACTORY_WATCH_ROOT` is the script root: `cd`, logs, `state/`, orders, `webhook.curl`, heartbeat, status, needs-scott, and `PAUSE`. `FACTORY_BUDGET_FILE` and `FACTORY_LEDGER_FILE` are the budget and ledger paths. `FACTORY_CLONE_ROOT` is the parent of the `wo-<owner>_<repo>-<issue>-*` build clones that `push-protected.sh` pushes. `LANE` stays as it is in the lane scripts. The committed default is `main`.

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

## Board constants

`board-sync.sh` copies factory labels onto the Software Factory project. These project node ids are committed constants, not environment variables:

- `PROJ` `PVT_kwHOAYEAOs4Bo3vn`
- `FIELD` `PVTSSF_lAHOAYEAOs4Bo3vnzhnV1ik`
- Triage `cdd562ca`, Ready `84a24ea9`, Building `ed952d58`, Gate `9cfe6bd1`, Review `befc9395`, Merge `240a84ea`, Release `d53e0069`, Blocked `c59dd1a6`, Done `037f9c49`
