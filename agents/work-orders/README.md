# Work orders

One file per source issue, written by the foreman: `<owner>_<repo>-<issue>.md`
using `issue_repo` (for example `adamsuk_software-factory-19.md`). Branches use
`factory/<issue-repo-slug>/<issue>-<short-slug>` (AGENTS.md §2), even when the
target `repo` differs. The format is in
[`../roles/foreman.md`](../roles/foreman.md#work-order-format). Run one with
`scripts/run-work-order.sh [--push] <file>`.
