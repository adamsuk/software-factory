# Station container: preparing a host

Stations (intake, foreman, reviewer and the rest) run in a
container on a network with one way out: an allow-listing proxy (#418). This
page is the host side: two images, one internal network, one proxy container
and one credential. `docs/runbooks/work-order-container.md` covers the same
settings for the builder in `scripts/run-work-order.sh`; the two share them.

Run end to end on one host on 2026-11-15: rootless podman 5.7.0 with netavark,
Ubuntu. docker and nerdctl have not been tried.

## 1. Build the images

```bash
scripts/build-station-image.sh
```

This builds `localhost/factory-station:claude-<version>` and
`localhost/factory-egress-proxy:1`. The base images are pinned by digest and
the Claude Code CLI by version, all in that script. `--print` shows the build
commands without running them.

The station image holds bash, git, gh, jq, python3 with PyYAML, shellcheck and
the `claude` CLI. It holds no credential and copies nothing from the host.

## 2. Create the network and start the proxy

```bash
podman network create --internal factory-egress
```

```bash
podman network create factory-egress-out
```

```bash
podman run -d --name factory-egress-proxy --restart unless-stopped --network factory-egress-out --network factory-egress localhost/factory-egress-proxy:1
```

`factory-egress` is internal: a container on it has no route to any other
host. The proxy sits on both networks, so it is the only way out. It needs the
second network to be one with DNS (a network you create, not podman's default
`podman` network), or it cannot resolve the hosts it is allowed to reach.

The proxy allows `CONNECT` to port 443 on the hosts in
`containers/egress-proxy/allowlist.txt` and refuses everything else:

| Host | Why |
| --- | --- |
| `api.anthropic.com` | Claude Code's model API |
| `api.x.ai` | Grok's model API |
| `api.github.com`, `github.com` | `gh` reads, `scripts/station-post.sh` writes, git fetch and push |

A change to that list is a change to the file and a rebuild of the proxy image.

## 3. Check it

Each of these should print what the comment says.

```bash
podman run --rm --network factory-egress -e HTTPS_PROXY=http://factory-egress-proxy:8888 localhost/factory-station:claude-2.1.322 curl -sS -o /dev/null -m 15 -w '%{http_code}\n' https://api.github.com/   # 200
```

```bash
podman run --rm --network factory-egress -e HTTPS_PROXY=http://factory-egress-proxy:8888 localhost/factory-station:claude-2.1.322 curl -sS -o /dev/null -m 15 -w '%{http_code}\n' https://example.com/   # 000, CONNECT tunnel failed
```

```bash
podman run --rm --network factory-egress localhost/factory-station:claude-2.1.322 curl -sS -o /dev/null -m 8 -w '%{http_code}\n' https://api.github.com/   # 000, no route without the proxy
```

On 2026-11-15 the first printed 200, `api.anthropic.com` answered 404 at `/`
(reachable), and `example.com`, `raw.githubusercontent.com` and the no-proxy
case all failed as intended.

## 4. The provider credential

The container has no home directory from the host, so the CLI's own login is
not there. Claude Code takes a long-lived token from the environment instead:

```bash
claude setup-token
```

Export what it prints as `CLAUDE_CODE_OAUTH_TOKEN` in the shell (or service)
that starts stations. Never commit it, and never put it in an image. Grok takes
`XAI_API_KEY` the same way.

## 5. What to export

```bash
export FACTORY_CONTAINER_IMAGE=localhost/factory-station:claude-2.1.322
```

```bash
export FACTORY_CONTAINER_NETWORK=factory-egress
```

```bash
export FACTORY_CONTAINER_PROXY=http://factory-egress-proxy:8888
```

Checking a host, names only:

```bash
echo "${FACTORY_CONTAINER_IMAGE:-unset}" "${FACTORY_CONTAINER_NETWORK:-unset}" "${FACTORY_CONTAINER_PROXY:-unset}" "${CLAUDE_CODE_OAUTH_TOKEN:+token set}"
```

## What starts in the container

`scripts/station-run.sh` starts every provider adapter in it, and the watcher's
non-Grok provider calls go through `scripts/station-container.sh`, which builds
the same container. Both exit 9 and start nothing when the runtime, the image,
the restricted network or the provider credential is missing. `--dry-run` needs
none of it.

| In the container | Not in the container |
| --- | --- |
| The working tree, read-write: the real checkout for a writing role (foreman, builder), a throwaway clone for a reading one | The original checkout, for a reading role |
| The start-of-run snapshot of `scripts/`, `adapters/` and the prompts, read-only | This host's home directory, `gh` login and ssh agent |
| The prompt bundle, and the work order file, read-only | The App key file and every other repository on the box |
| The provider's own credential and `GH_TOKEN`, forwarded by name | Every other environment variable, other providers' credentials included |

`GH_TOKEN` has to be in the environment, or `FACTORY_GH_APP_ID` and its two
companions set so `station-run.sh` mints an installation token. The watcher
forwards no GitHub token: it does the GitHub writes itself.

The container runs as the calling user, with all capabilities dropped. It must
not be root: Claude Code refuses to run with approval off as root, and rootless
podman maps the caller to root unless `--userns keep-id` is passed, which the
scripts do.

Checked on 2026-11-15 from a real container on this setup: `gh api` and
`git ls-remote` worked through the proxy, `example.com` was refused, `/home`
held nothing of the host, the App key file and the real checkout were not
there, a file written in the working tree was owned by the calling user, and a
read-only mount could not be written. A reviewer station run with a
deliberately invalid token reached the model API and was answered `401 Invalid
bearer token`. A run with a valid token has not been done yet.

Not covered: the Grok builder clones and pushes on the host through
`scripts/run-work-order.sh`, and the watcher's Grok calls still start `grok`
on the host.

## Known traps

- **AppArmor and tinyproxy.** Ubuntu ships an AppArmor profile attached to
  `/usr/bin/tinyproxy`. It applies inside a rootless container too and stops
  the proxy reading its filter file (`filter file: Permission denied`, exit
  65). The proxy image installs the binary as `/usr/local/bin/egress-proxy` for
  that reason.
- **Proxy DNS.** Attached to the internal network and podman's default network
  only, the proxy answered every request with 500 and logged `Name does not
  resolve`. The second network has to be a user-created one.
- **Plain HTTP.** The proxy also forwards plain HTTP on port 80 to the allowed
  hosts. Nothing a station uses needs it.
- **The builder's image.** `scripts/run-work-order.sh` needs an image with the
  target repo's test tools as well. The station image is enough for this repo's
  own tests; another repo may need its own.
