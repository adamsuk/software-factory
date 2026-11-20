# Local watcher: running both lanes on one machine

Bring up the main and build watcher lanes on a maintainer's own machine. This
makes the location of the watcher known (so #382 becomes answerable) and
gives a preflight that names every variable it checks.

Part of #386. Does not change the watcher itself.

## Variables the preflight checks

| Variable | Required | Meaning |
| --- | --- | --- |
| `FACTORY_PROVIDER` | no | `grok`, `claudecode` or `opencode` (default `grok`). |
| `FACTORY_CONTAINER_IMAGE` | for container builds | Image that carries the model CLI. |
| `FACTORY_CONTAINER_NETWORK` | for container builds | `none` or an internal network name. |
| `FACTORY_CONTAINER_PROXY` | no | `http(s)://host[:port]`, no credentials. |
| `FACTORY_CONTAINER_RUNTIME` | no | `podman`, `docker`, `nerdctl` or a path. Unset: first on PATH. |
| `FACTORY_GROK_ON_HOST` | no | Set to the exact phrase `host-is-a-disposable-sandbox` to start `grok` on the host when no container runtime is available. |
| `FACTORY_WATCH_ROOT` | no | Directory that holds the lane scripts. |
| `FACTORY_HOME` | no | State directory (default under `~/.local/share/software-factory`). |

The preflight also checks:

- `gh` is on PATH and `gh auth status` succeeds (login present).
- The chosen provider's CLI is on PATH (or `FACTORY_GROK_BIN` for grok).
- The provider's credential name is set (value is never printed): `XAI_API_KEY` for grok, `CLAUDE_CODE_OAUTH_TOKEN` for claudecode, one of the opencode keys.
- A container runtime is present, **unless** `FACTORY_GROK_ON_HOST` is the exact sandbox phrase.
- The state directory exists and is writable.

Names only are ever printed. Values are never echoed (AGENTS.md §7).

## Bypass the container (podman / docker / nerdctl)

The builder (`scripts/run-work-order.sh`) and stations refuse to start without a
container runtime and an internal network. On a machine that cannot run one
(for example a shared Grok Bot computer), set:

```bash
export FACTORY_GROK_ON_HOST=host-is-a-disposable-sandbox
```

This lets the watcher's Grok launches run on the host. It is weaker than the
container (see the 2026-11-16 changelog entry). Stations still require the
container. Prefer a real runtime when the host can provide one.

## Start both lanes

After the preflight exits zero:

```bash
# systemd --user (preferred when available)
systemctl --user start factory-watcher-main.service
systemctl --user start factory-watcher-build.service

# or a simple start script
./scripts/watcher/start-lanes.sh   # if present; otherwise call watch.sh / watch.new.sh directly
```

See `scripts/watcher/README.md` for the lane scripts themselves.

## Related

- `docs/runbooks/work-order-container.md` — the builder container.
- `docs/runbooks/station-container.md` — the station container.
- `FACTORY_WATCHER_BUILDS=off` — a host that only watches and never builds.
