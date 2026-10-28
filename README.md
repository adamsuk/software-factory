# software-factory

Private home for Scott's end-to-end software factory: the backlog of changes,
and the audits that drive it.

It's private on purpose. The audits record security gaps (agents using the
owner token, unprotected `main`, no production approval gate), and they belong
here rather than in public tooling.

## Long-term aim

- **A generic repo setup:** every repo under touchlineHQ and adamsuk gets the
  same baseline (settings, rulesets, labels, starter files) from
  [adamsuk/gh-factory](https://github.com/adamsuk/gh-factory).
- **As much shared automation as possible:** reusable workflows hosted in
  gh-factory, and the Grok Bot agents (Issue Shipper, PR Reviewer, Signal
  Issues, Research Scout) running from reviewable, versioned instructions under
  their own identity.
- **Measured against [Line](https://adamsuk.github.io/line/):** a periodic
  read-only audit scores each Line recommendation, and the gaps become issues
  here.

## How the pieces fit

| Piece | Where | Visibility |
| --- | --- | --- |
| Generic baseline and the `gh factory` CLI | [adamsuk/gh-factory](https://github.com/adamsuk/gh-factory) | public, reusable |
| The guide audits are scored against | [adamsuk/line](https://github.com/adamsuk/line) | public |
| Audits, backlog and decisions | this repo, and the "Software Factory" GitHub Project | **private** |
| Delivery repos | touchlineHQ/clubsPlatform, fulltimeFeeds, touchlineHQ, .github | org |
| Agents | Grok Bot: Issue Shipper, PR Reviewer, Signal Issues, Research Scout | — |

A backlog issue in this repo names one target repository. Issue Shipper does
not pick issues in other repositories on its own.

## Agents

The factory's agents share one set of rules and one brief per role, kept here
so changes to them are reviewed like code (#17):

- [`AGENTS.md`](AGENTS.md): rules every agent follows, Grok Build included.
- [`agents/roles/`](agents/roles): `foreman` (the Software Factory bot),
  `intake` (Signal Issues), `research` (Research Scout), `builder` (Issue
  Shipper, and Grok Build under the foreman) and `reviewer` (PR Reviewer).
- [`agents/grok-build.md`](agents/grok-build.md) and
  [`scripts/run-work-order.sh`](scripts/run-work-order.sh): how the foreman
  runs Grok Build headless on one work order.

Which roles run in a repo, and whether agents may merge there, is set per repo
in `.github/factory.yml` under `agents:` (merging is off by default).

### Review workflow setup

`scripts/review-issue.sh` requires Bash, Python 3 with venv/pip, PyYAML,
`jq`, and an authenticated GitHub CLI (`gh`) **2.50 or newer**:
`scripts/gate-issue.sh` reads check results with `gh pr checks --json`, which
older builds do not have. Without PyYAML the gate stops and names the missing
module. From this repo's root, prepare
and activate an environment before running the review script:

```bash
python3 -m venv ../software-factory.venv
source ../software-factory.venv/bin/activate
python3 -m pip install -r requirements.txt
scripts/review-issue.sh /path/to/work-order.md
```

Use the same activated environment for `bash scripts/test-review-issue.sh`;
the tests use a fake `gh` and do not contact GitHub. The work-order runner's
automatic Python setup also installs `requirements.txt` into its virtual
environment. Shell lint requires `shellcheck` (`shellcheck scripts/*.sh`).

## Audits

- [`audits/2026-10-24.md`](audits/2026-10-24.md): the first Line audit.
- [`audits/2026-10-25.md`](audits/2026-10-25.md): the re-run after gh-factory
  existed. The per-gap backlog (#2 to #40) is based on this one.
- [`audits/2026-10-26.md`](audits/2026-10-26.md): the re-run after the agent
  rules and Grok Build landed. Its gaps are grouped into one ticket per Line
  station (label `station`, #43 to #51).
- [`audits/2026-10-28.md`](audits/2026-10-28.md): the first audit scoped to
  **this repo alone**, against guide v2026-10-27 (27 recommendations: 2 met, 13
  partial, 12 missing). Its gaps are prioritised `P0` to `P3` under one parent,
  #134, that spans all nine stations.

Audits are read-only and never print secret values.

## Working from the board

The [Software Factory board](https://github.com/users/adamsuk/projects/2) is the
place to work. `scripts/watcher/board-sync.sh` keeps it in step with the labels,
one way only: **labels are the source of truth** (AGENTS.md §9), so nothing the
board shows can overwrite them, and nothing can loop.

It runs two passes for two different reasons. Membership has no date window, so
every open issue and pull request reaches the board however long ago it was
touched. The `factory status` mirror keeps a 2-day window, because a label that
has not changed in two days needs no write.

### Flagging work

Add **`priority: next`** to an issue from the board's item pane (show Labels as
a board field). More than one issue may carry it.

It is additive on purpose. §9 allows exactly one `factory:*` label, so flagging
with `factory:ready` would mean displacing an issue's real state — a
`factory:blocked` ticket would stop looking blocked. `priority: next` sits
alongside whatever status the issue already has.

Then ask for the flagged work. Nothing is picked up unattended:

```bash
scripts/factory-flagged.sh
```

That lists the flagged issues in the order to work them — `priority: P0` first,
then P1, P2, P3, unprioritised last, and by issue number within a priority. It
is read-only and picks up nothing itself.

Each flagged issue still goes through the stations
([`stations/README.md`](stations/README.md)), and merging stays with Scott
(`agents.merge: false`).

### What the board needs

`gh project` calls need the `project` scope, which a plain `repo` token does not
carry:

```bash
gh auth refresh -s project
```

Without it `board-sync.sh` fails with `missing required scopes [read:project]`.
`scripts/factory-flagged.sh` reads labels, not the board, so it works either way.

## Backlog labels

| Label | Meaning |
| --- | --- |
| `best practice` / `cutting edge` | Exactly as Line classifies the recommendation. Never re-graded here. |
| `audit-2026-10-25` | Raised by that audit |
| `audit-2026-10-28` | Raised by that audit |
| `area: repo setup` | Repo settings, rulesets, CODEOWNERS, templates |
| `area: delivery & release` | Environments, releases, Dependabot, provenance |
| `area: agents & automation` | Agent identity, briefs, review, fix loops, evals |
| `area: observability` | Metrics, drift and re-audits |
| `area: gh-factory` | Changes to the gh-factory tool or baseline |
| `quick win` / `big gain` | As the audit lists them under quick wins or biggest gains |
| `decision` | Needs Scott's call before anyone acts |
| `station` / `station: NN <name>` | Creates or runs one Line station (01 Backlog to 09 Return) |
| `priority: next` | Flagged for pickup from the board. May be on several issues; work them in `priority: P0`-`P3` order with [`scripts/factory-flagged.sh`](scripts/factory-flagged.sh). Additive, so it never displaces a `factory:*` status. |
| `priority: P0` / `P1` / `P2` / `P3` | Urgent, high, medium, low. Set by an audit; Scott re-ranks. |
| `factory:triage`, `factory:ready`, `factory:building`, `factory:gate`, `factory:review`, `factory:merge`, `factory:release`, `factory:done`, `factory:blocked` | Exactly one status label at a time. Who sets each one is in [AGENTS.md section 9 (Status labels)](AGENTS.md#9-status-labels-43). |

The [Software Factory](https://github.com/users/adamsuk/projects) GitHub
Project tracks the same issues with Type, Area, Effort, Target repo and Audit
date fields.
