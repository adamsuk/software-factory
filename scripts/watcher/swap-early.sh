#!/usr/bin/env bash
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
cd "$FACTORY_WATCH_ROOT"
# The lanes load factory-env.sh from beside themselves, so it ships with them: a
# staged factory-env.sh.early moves into place first. With no factory-env.sh
# here at all, stop before any lane is stopped; the new lane would not start.
if [[ -f factory-env.sh.early ]]; then
  if [[ -f factory-env.sh ]]; then cp factory-env.sh factory-env.sh.pre-early; fi
  mv factory-env.sh.early factory-env.sh
fi
[[ -r factory-env.sh ]] || { echo "swap-early: no factory-env.sh in $FACTORY_WATCH_ROOT; stage factory-env.sh.early first" >&2; exit 1; }
sw(){ local log=$1 file=$3 lock=$4 envs=$5
  until tail -1 "$log" | grep -q 'sleep 180$'; do sleep 10; done
  pkill -f "^bash ./$file"; sleep 1; for p in $(fuser "$lock" 2>/dev/null); do kill "$p" 2>/dev/null; done; sleep 1
  cp "$file" "$file.pre-early"; mv "$file.early" "$file"
  env ${envs:+"$envs"} setsid nohup bash ./"$file" >> nohup.out 2>&1 < /dev/null &
  echo "$(date -u +%FT%TZ) swapped $file: dismiss coderabbitai CHANGES_REQUESTED on PASS merges" >> swap.log; }
sw watch-build.log x watch.new.sh watch-build.lock LANE=build
sw watch.log x watch.sh watch.lock ""
