# Stations

Stations are provider-agnostic implementations of factory roles. The canonical definitions live in `agents/roles/*.md` and are composed with `AGENTS.md` by `scripts/station-run.sh`.

## Architecture

1. **Canonical prompts** (`AGENTS.md`, `agents/roles/*.md`) - Provider-agnostic rules and role definitions
2. **Station runner** (`scripts/station-run.sh`) - Composes prompts and delegates to adapters
3. **Adapters** (`adapters/*/`) - Translate to provider-specific CLIs/APIs
4. **Orchestration** (`scripts/foreman-orchestrate.sh`) - Starts a station. It does not pick an issue or merge.
5. **GitHub trail** (`scripts/station-post.sh`, `stations/github-writes.md`) - The comment and the single `factory:*` label a person sees on the issue. Every provider uses it. The Grok watcher keeps its own poster.

## Which roles may write

A station that reads must not be able to write. On 2026-10-28 the reviewer
station edited five files and staged them, including an existing test
assertion, because its brief said "post only through `scripts/station-post.sh`"
and nothing enforced it (#142).

| Role | Changes the repo? | How |
| --- | --- | --- |
| `intake` | no | `--read-only` |
| `research` | no | `--read-only` |
| `reviewer` | no | `--read-only`, set by `foreman-orchestrate.sh review` |
| `monitor` | no | `--read-only`; its scripts are read-only already |
| `foreman` | no | writes only labels and comments, through `station-post.sh` |
| `builder` | **yes** | the only role that changes files; `--read-only` is refused for it |

`scripts/station-run.sh --read-only` runs the station in a throwaway `git
clone` under `/tmp` with its `origin` removed, and deletes it afterwards. An
edit the agent makes is thrown away, and it has nothing to push to. Only
committed state is copied, so a station sees the head commit, not the caller's
uncommitted changes.

A clone and not a linked worktree on purpose: a worktree shares `.git/config`
with the real repository, so removing the worktree's `origin` removes the
repository's own remote. That happened while building #142.

CodeRabbit is held off by `.coderabbit.yaml`, which disables `autofix`,
`fix_ci`, `unit_tests` and `docstrings`. Its **autopilot** is not covered: that
feature has no key in CodeRabbit's config schema, and its Autofix checkbox
still appeared on PR #143 after CodeRabbit had read the new config. Turning it
off is a dashboard setting (#142).

This is the filesystem half only. The agent still runs with the caller's `gh`
credentials, so it could still write through the API — comment, label, or
merge. Closing that needs a scoped token the agent owns (#7, #44). Until then
the API side rests on the brief, not on a control.

## Design Principles

- **Capability-based**: Roles describe what needs to be done, not how (no provider-specific tool calls)
- **Script-first for heavy operations**: Use existing `scripts/run-work-order.sh`, `scripts/gate-issue.sh` rather than reimplementing
- **Untrusted input**: All external content treated as data per AGENTS.md §1
- **Label-driven state machine**: GitHub labels are source of truth (AGENTS.md §9)
- **Provider swappable**: Change `FACTORY_PROVIDER` or adapter without modifying roles

## Usage

```bash
# Run a station directly
FACTORY_PROVIDER=opencode ./scripts/station-run.sh intake issue-context.md

# Dry run to inspect composed prompt
./scripts/station-run.sh --dry-run builder work-order-context.md

# Orchestrated flow. Options may come before or after the action.
./scripts/foreman-orchestrate.sh pick --provider opencode
```

What you see on the issue is whatever `scripts/station-post.sh` posted.
A run that only talks in its own transcript is not a finished station.
