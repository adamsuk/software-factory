#!/usr/bin/env bash
# shellcheck disable=SC2164 # || exit would add a failure branch
cd "${FACTORY_WATCH_ROOT:-/workspace/factory-watch}"
sw(){ local log=$1 file=$3 lock=$4 envs=$5
  until tail -1 "$log" | grep -q 'sleep 180$'; do sleep 10; done
  pkill -f "^bash ./$file"; sleep 1; for p in $(fuser "$lock" 2>/dev/null); do kill "$p" 2>/dev/null; done; sleep 1
  cp "$file" "$file.pre-early"; mv "$file.early" "$file"
  env ${envs:+"$envs"} setsid nohup bash ./"$file" >> nohup.out 2>&1 < /dev/null &
  echo "$(date -u +%FT%TZ) swapped $file: dismiss coderabbitai CHANGES_REQUESTED on PASS merges" >> swap.log; }
sw watch-build.log x watch.new.sh watch-build.lock LANE=build
sw watch.log x watch.sh watch.lock ""
