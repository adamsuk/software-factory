# Stations

Stations are provider-agnostic implementations of factory roles. The canonical definitions live in `agents/roles/*.md` and are composed with `AGENTS.md` by `scripts/station-run.sh`.

## Architecture

1. **Canonical prompts** (`AGENTS.md`, `agents/roles/*.md`) - Provider-agnostic rules and role definitions
2. **Station runner** (`scripts/station-run.sh`) - Composes prompts and delegates to adapters
3. **Adapters** (`adapters/*/`) - Translate to provider-specific CLIs/APIs
4. **Orchestration** (`scripts/foreman-orchestrate.sh`) - State machine logic using existing label/scripts

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

# Orchestrated flow (foreman manages state machine)
./scripts/foreman-orchestrate.sh --provider opencode pick
```
