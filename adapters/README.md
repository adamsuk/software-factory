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

OpenCode attaches the prompt with `opencode run --file`. It does not take
`--prompt-file`. The station prompt includes `stations/github-writes.md`:
comments and `factory:*` labels go through `scripts/station-post.sh`, which
is what shows the run on the issue. The adapter does not merge.

Claude Code takes neither: the bundle goes in on stdin in print mode (`-p`),
and `AGENTS.md` is appended to the system prompt, which is that CLI's
equivalent of grok's `--rules`.

## Probing, not assuming

An adapter asks the CLI what it supports rather than assuming a version.
`opencode run` rejected `--dir` outright in v2.2.0, which stopped every station
on that provider until #140; the adapter now probes for the flag and enters the
repo root itself when it is absent. Fail with a message that says which of the
three things went wrong: the CLI is missing, the CLI lacks a flag the role
needs, or the arguments were wrong. `scripts/test-adapters.sh` covers that
contract for all three providers with fake CLIs on `PATH`.

## Role coverage

`builder` runs only on grok, because `scripts/run-work-order.sh` invokes the
grok CLI directly. Every other role runs from the composed bundle on any
provider. Making the builder provider-agnostic needs that script changed and is
not done yet.

## Available Adapters

- `opencode/` - OpenCode CLI adapter
- `grok/` - Grok CLI adapter (uses existing `scripts/run-work-order.sh` for builder)
- `claudecode/` - Claude Code adapter (non-builder roles)

## Adding a New Provider

1. Create `adapters/<provider>/run.sh`
2. Make it executable
3. Implement the interface above
4. Set `FACTORY_PROVIDER=<provider>` or pass `--provider`
