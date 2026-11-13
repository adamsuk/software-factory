# Work-order container: what the host must provide

`scripts/run-work-order.sh` runs the grok child in a fresh container (#221) on a
restricted network (#382). It exits 9, before any model call, when one of these
is missing. Nothing here has a default on purpose.

| Variable | Meaning |
| --- | --- |
| `FACTORY_CONTAINER_RUNTIME` | Optional. `podman`, `docker` or `nerdctl`, or a path to one. Unset: the first of those three on `PATH`. |
| `FACTORY_CONTAINER_IMAGE` | Required. An image that carries the `grok` CLI and whatever the target repo's tests need. |
| `FACTORY_CONTAINER_NETWORK` | Required. `none`, or the name of a network the runtime reports as internal. |
| `FACTORY_CONTAINER_PROXY` | Optional. `http(s)://host[:port]`, no credentials. Set as `HTTPS_PROXY`, `HTTP_PROXY` and the lower-case forms inside the container. |

## What the script checks

- `host`, `bridge`, `default`, `private`, `podman`, `slirp4netns` and `pasta` are
  refused: they can reach any host.
- Any other name must exist (`<runtime> network inspect <name>`) and the output
  must say `"internal": true`. An internal network has no route out.
- `none` is accepted, but the grok child then cannot reach the model API, so it
  only suits a build that makes no model call.

The script checks that the network is internal. It cannot check what the proxy
allows: that list is the operator's, and it should hold the model API host only.

## Shape of the host setup

1. Create an internal network, for example `podman network create --internal factory-egress`.
2. Run an allowlisting forward proxy attached to both that network and an
   ordinary one, allowing `CONNECT` to the model API host on port 443 and
   nothing else.
3. Export `FACTORY_CONTAINER_NETWORK=factory-egress` and
   `FACTORY_CONTAINER_PROXY=http://<proxy-name>:<port>` where the watcher or the
   builder is started.

These three steps describe the intended shape. They have not been run end to end
on a factory host: the first real build is the test, and nerdctl in particular
may not report `internal` in its inspect output, in which case the script stops
with exit 9.

## Checking a host, names only

```bash
echo "${FACTORY_CONTAINER_IMAGE:-unset}" "${FACTORY_CONTAINER_NETWORK:-unset}" "${FACTORY_CONTAINER_PROXY:-unset}"
```
