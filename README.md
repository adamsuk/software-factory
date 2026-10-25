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
| Delivery repos | touchlineHQ/[private reference redacted], [private reference redacted], touchlineHQ, .github | org |
| Agents | Grok Bot: Issue Shipper, PR Reviewer, Signal Issues, Research Scout | — |

Backlog issues live here, **not** in touchlineHQ repos, because Issue Shipper
auto-picks issues there. When an item is ready to build, a scoped issue is
opened in the target repo.

## Audits

- [`audits/2026-10-24.md`](audits/2026-10-24.md): the first Line audit.
- [`audits/2026-10-25.md`](audits/2026-10-25.md): the re-run after gh-factory
  existed. The current backlog is based on this one.

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

The [Software Factory](https://github.com/users/adamsuk/projects) GitHub
Project tracks the same issues with Type, Area, Effort, Target repo and Audit
date fields.
