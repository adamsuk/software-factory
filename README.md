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

Audits are read-only and never print secret values.

## Backlog labels

| Label | Meaning |
| --- | --- |
| `best practice` / `cutting edge` | Exactly as Line classifies the recommendation. Never re-graded here. |
| `audit-2026-10-25` | Raised by that audit |
| `area: repo setup` | Repo settings, rulesets, CODEOWNERS, templates |
| `area: delivery & release` | Environments, releases, Dependabot, provenance |
| `area: agents & automation` | Agent identity, briefs, review, fix loops, evals |
| `area: observability` | Metrics, drift and re-audits |
| `area: gh-factory` | Changes to the gh-factory tool or baseline |
| `quick win` / `big gain` | As the audit lists them under quick wins or biggest gains |
| `decision` | Needs Scott's call before anyone acts |
| `station` / `station: NN <name>` | Creates or runs one Line station (01 Backlog to 09 Return) |
| `priority: next` | The one station ticket to build next |
| `factory:triage`, `factory:ready`, `factory:building`, `factory:gate`, `factory:review`, `factory:merge`, `factory:release`, `factory:done`, `factory:blocked` | Exactly one status label at a time. Who sets each one is in [AGENTS.md section 9 (Status labels)](AGENTS.md#9-status-labels-43). |

The [Software Factory](https://github.com/users/adamsuk/projects) GitHub
Project tracks the same issues with Type, Area, Effort, Target repo and Audit
date fields.
