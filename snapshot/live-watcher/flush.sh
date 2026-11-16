#!/usr/bin/env bash
# Every 120s: POST pending factory events to the Factory events routine webhook (never prints webhook.curl).
cd /workspace/factory-watch; P=state/events-pending.txt
while true; do [[ 10#$(TZ=Europe/London date +%H) -ge 7 ]] || { sleep 300; continue; };
  ( flock -w 60 7 || exit 0
    [[ -s $P ]] || exit 0
    jq -Rs '{source:"factory-watch", events:(split("\n")|map(select(length>0)))}' $P > state/flush-payload.json || exit 0
    http=$(curl -sS -m 20 -K webhook.curl -H 'Content-Type: application/json' --data-binary @state/flush-payload.json -o /dev/null -w '%{http_code}' 2>>flush.err)
    if [[ $http =~ ^2 ]]; then cat $P >> state/events-sent.log; : > $P; echo "$(date -u +%FT%TZ) sent" >> flush.log
    else echo "$(date -u +%FT%TZ) http=$http" >> flush.log; fi
  ) 7>state/events.lock
  sleep 120
done
