# Provider Adapters

Adapters translate provider-agnostic station execution into provider-specific invocations.

## Structure

- Each provider gets a directory under `adapters/<provider>/`
- Each adapter must provide `run.sh` (executable) that accepts:
  - `--role <role>` - Station role name
  - `--prompt <path>` - Path to composed prompt bundle (includes AGENTS.md + role + context)
  - `--work-order <path>` - Optional work order path
  - `--issue <n>` - Optional issue number
  - `--repo <owner/repo>` - Optional repo
  - Additional args passed through

## Usage

```bash
# Via station-runner (preferred)
./scripts/station-run.sh --provider opencode foreman /path/to/context

# Or directly
./adapters/opencode/run.sh --role foreman --prompt /tmp/prompt.md
```

## Available Adapters

- `opencode/` - OpenCode CLI adapter
- `grok/` - Grok CLI adapter (uses existing `scripts/run-work-order.sh` for builder)
- `claudecode/` - Claude Code adapter (placeholder)

## Adding a New Provider

1. Create `adapters/<provider>/run.sh`
2. Make it executable
3. Implement the interface above
4. Set `FACTORY_PROVIDER=<provider>` or pass `--provider`
