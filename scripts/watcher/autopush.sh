#!/usr/bin/env bash
# Every 60s: for builds that exited 4 (protected paths) on issues the maintainer approved, push and open the PR.
# >>> factory env: the shared settings live in factory-env.sh, beside this script.
factory_env_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/factory-env.sh"
if [[ ! -r $factory_env_file ]]; then
  printf '%s: cannot read %s (factory-env.sh must sit beside the watcher scripts)\n' "${BASH_SOURCE[0]##*/}" "$factory_env_file" >&2
  exit 1
fi
# shellcheck source=scripts/watcher/factory-env.sh
source "$factory_env_file"
# <<< factory env
# shellcheck disable=SC2164 # || exit would add a failure branch
cd "$FACTORY_WATCH_ROOT"; touch state/autopush-done.txt
while true; do [[ $((10#$(TZ=Europe/London date +%H))) -ge 7 ]] || { sleep 300; continue; };
  grep -ho 'run-work-order failed rc=4 for [^;]*' watch.log watch-build.log 2>/dev/null | awk '{print $NF}' | sort -u | while read -r ref; do
    grep -qxF "$ref" state/autopush-done.txt && continue
    url=$(./push-protected.sh "${ref%#*}" "${ref#*#}" 2>&1 | tail -1)
    if [[ $url == https://* ]]; then
      echo "$ref" >> state/autopush-done.txt
      ( flock 9; echo "$(date -u +%FT%TZ) needs-scott protected PR opened for $ref: $url (the maintainer merges)" >> state/events-pending.txt ) 9>state/events.lock
      echo "$(date -u +%FT%TZ) $ref -> $url" >> autopush.log
    else echo "$(date -u +%FT%TZ) $ref skipped: $url" >> autopush.log; echo "$ref" >> state/autopush-done.txt; fi
  done
  sleep 60
done
