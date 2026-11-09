---
repo: adamsuk/software-factory
issue: 295
issue_repo: adamsuk/software-factory
title: "feat: portable script and watcher defaults via env vars"
branch: factory/295-portable-defaults
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh && bash scripts/test-adapters.sh && bash scripts/test-check-test-assertions.sh && bash scripts/test-factory-flagged.sh && bash scripts/test-run-work-order.sh && bash scripts/test-run-work-order-llm.sh && bash scripts/test-station-run.sh && bash scripts/test-wait-for-review-bot.sh && bash scripts/test-research-brief.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-11-09
---

## Goal

Make the scripts and watcher run on any machine and for any owner. Several defaults are specific to the original host: fixed absolute directories, one GitHub owner and repo list, one approver login, one hard-coded blocked organisation, a fixed project board and its node IDs, a machine-specific secrets path in the Claude Code deny rule, and the maintainer's personal name in posted messages. Replace these with env vars that have portable defaults, and document them.

Size: L (protected: changes existing test assertions)

## Authorisation

The maintainer authorised these protected-path edits on 9 Nov 2026 (Europe/London), solely for this generalisation. Where an existing test asserts an old literal, update the assertion to the configurable equivalent. Never weaken what it checks. Every deny-list needle, including the `/home/` and `/Users/` checks in `scripts/test-watcher-tree.sh`, stays. The maintainer will review and approve the PR.

## Change

- **`FACTORY_HOME`**, defaulting to `${XDG_DATA_HOME:-$HOME/.local/share}/software-factory`. Derive the other paths from it:
  - `FACTORY_WATCH_ROOT` defaults to `$FACTORY_HOME/factory-watch`.
  - `FACTORY_BUDGET_FILE` defaults to `$FACTORY_HOME/factory-budget.json`.
  - `FACTORY_LEDGER_FILE` defaults to `$FACTORY_HOME/factory-ledger.csv`.
  - `FACTORY_CLONE_ROOT` and `FACTORY_WORKSPACE` default to `$FACTORY_HOME`.

  Apply this in `scripts/run-work-order.sh` (`choose_clone_root`, keeping the loud temp-dir fallback) and in `scripts/watcher/{watch.sh,watch.new.sh,autopush.sh,swap-early.sh,push-protected.sh,board-sync.sh}`. With `FACTORY_HOME` set to a directory D, the resolved paths must be `D/factory-watch`, `D/factory-budget.json`, `D/factory-ledger.csv` and `D`.
- **`FACTORY_HOME_REPO`**: the repo that holds work orders and epics. It defaults to `$GITHUB_REPOSITORY`, then the `origin` remote of `git rev-parse --show-toplevel`, then `gh repo view --json nameWithOwner`. Every literal owner/`software-factory` slug in the watcher scripts uses it: the clone, the epic planner, the focus and close-ref regexes, and `Closes` lines.
- **`FACTORY_REPOS`**: a space-separated `owner/repo` list that defaults to `FACTORY_HOME_REPO`. Derive `REPO_NAMES_ALT` and `REPOS_HUMAN` from it without stripping a fixed owner prefix. `scripts/pr-status.sh`, `scripts/review-bot-metrics.sh` and `scripts/factory-flagged.sh` use it as their default.
- **`FACTORY_APPROVER_LOGIN`**: the human login whose comments count as approval or factory review. It defaults to the owner part of `FACTORY_HOME_REPO`. Use it in `scripts/review-issue.sh` and `scripts/watcher/push-protected.sh`. Replace the approval marker that contains the maintainer's personal name with the neutral marker `<!-- factory:approve -->`, and keep accepting the old marker for compatibility.
- **`FACTORY_BLOCKED_OWNERS`**: a space-separated list of owners the watcher must never clone, modify or merge. **There is no literal default in code**; unset means an empty list. It replaces the hard-coded organisation match and the prompt sentences that name that organisation. Prompts state the configured list generically.
- **Board configuration**: `FACTORY_BOARD_OWNER`, `FACTORY_BOARD_NUMBER`, `FACTORY_BOARD_PROJECT_ID`, `FACTORY_BOARD_FIELD_ID` and `FACTORY_BOARD_OPTIONS`. `FACTORY_BOARD_OPTIONS` is a JSON object that maps each status name to its option id. If any of them is unset, `board-sync.sh` prints "board sync not configured" and exits 0. No project or node IDs stay in code or docs.
- **Claude Code secrets deny rule** in `scripts/run-work-order.sh`: build it from the absolute `${FACTORY_SECRETS_DIR:-$HOME/.factory-secrets}` as `Read(/<absolute path>/**)`, keeping the leading `//` anchor. It replaces the literal machine path. The `Bash(*factory-secrets*)` guard stays.
- **`scripts/station-run.sh`**: change `mktemp -d /tmp/...` to `mktemp -d "${TMPDIR:-/tmp}/..."`.
- **Posted text**: "<maintainer> must act." becomes "The maintainer must act." in `scripts/gate-issue.sh`, `scripts/review-issue.sh`, `scripts/station-post.sh`, `scripts/check-test-assertions.sh` and the watcher messages, prompts and comments. Machine-readable markers and file names such as `needs-scott` may stay for compatibility, but posted text must not contain the personal name.
- **`scripts/watcher/README.md`**: replace the "Committed default" table with the new env vars and defaults. Document board settings as configuration. Add an "Environment" table to `README.md` that lists every variable above with its default.

## Existing tests to update (assertion moves to the configurable equivalent, never weaker)

- `scripts/test-watcher-tree.sh`: the README env topics and board constants.
- `scripts/test-run-work-order-llm.sh`: the deny-rule literal. Assert the rule derived from a fake `HOME` and from `FACTORY_SECRETS_DIR`.
- `scripts/test-run-work-order.sh`: the clone-root default.
- `scripts/test-factory-delivery-metrics.sh`: the ledger default.
- `scripts/test-gate-issue.sh`, `test-review-issue.sh`, `test-station-post.sh` and `test-red-check-record.sh`: the posted text.
- `scripts/test-watcher-dismiss.sh` and others: set `FACTORY_REPOS` and `FACTORY_HOME_REPO` in fixture env as needed.

Changing fixture owner names is a separate issue. Keep fixture owners as they are here, unless an assertion must change anyway.

## Acceptance criteria

- [ ] No fixed host directory or local Claude binary path in `scripts/*.sh scripts/watcher/*.sh`.
- [ ] `git grep -n adamsuk -- 'scripts/*.sh' 'scripts/watcher/*.sh' ':!scripts/test-*'` returns nothing.
- [ ] The private organisation name appears nowhere under `scripts/`.
- [ ] The maintainer's personal name appears nowhere in `scripts/*.sh` or `scripts/watcher/*` outside `scripts/test-*`.
- [ ] New tests prove the portable defaults. With none of the new vars set, a temporary `HOME` and no fixed host directory, each path resolves under `$HOME/.local/share/software-factory` (or `$XDG_DATA_HOME`).
- [ ] New tests prove that `FACTORY_HOME=D` resolves exactly to `D/factory-watch`, `D/factory-budget.json`, `D/factory-ledger.csv` and clone root `D`.
- [ ] A new test proves that `FACTORY_BLOCKED_OWNERS` blocks a listed owner and blocks nothing when unset.
- [ ] Every existing deny-list needle and safety check stays, including `/home/` and `/Users/` in `scripts/test-watcher-tree.sh`.
- [ ] The full test suite passes on a machine without the original host directories. That means CI on ubuntu-latest, plus `agents.test_command` and `scripts/test-watcher-tree.sh` run locally with those paths masked and a fake `HOME`.
- [ ] `README.md` lists every env var with its default.
- [ ] `CHANGELOG.md` gains exactly one new dated entry. Existing entries, `audits/`, `metrics/`, `LICENSE` and existing work-order records are not edited.
- [ ] `AGENTS.md`, `agents/roles/**`, `agents/grok-build.md` and `.github/**` are not edited. Their wording is a separate issue.

## Out of scope

- Changing fixture owner names. That is a separate issue.
- Deploying to any running watcher.
- Approving or merging.

## Builder notes

- watch.sh and watch.new.sh are near-duplicates; apply the same change to both.
- The watcher README says no script sources another file. Keep that true: inline the short path/env resolution in each watcher script, identically.
- Run `agents.test_command` plus every extra test named in the acceptance criteria before finishing, and fix failures.
- Do not write the private delivery organisation's name anywhere.

Bookkeeping copy. Literal host paths, the personal name and the private organisation name from the original order are paraphrased here so the copy itself stays portable.
