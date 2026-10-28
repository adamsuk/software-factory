#!/usr/bin/env bash
# Every 3 min (07:00-24:00 London): keep the Software Factory project board
# (adamsuk project 2) in step with the factory labels.
#
# Two passes, because membership and status want different windows:
#   1. Membership. Every open issue and pull request belongs on the board,
#      however long ago it was touched. Without this an item that goes quiet
#      before it is added is never added, which is why the board was missing
#      tickets (#145).
#   2. Status. Mirrors the single factory:* label onto the board's
#      `factory status` field, over a 2-day window. The window is right here:
#      a label that has not changed in two days needs no write.
#
# Labels are the source of truth (AGENTS.md section 9). This sync is one-way,
# labels -> board, so nothing it does can loop. Flagging for pickup is the
# `priority: next` label, set from the board item pane, which this script does
# not read and does not need to.
# shellcheck disable=SC2164 # || exit would add a failure branch
cd "${FACTORY_WATCH_ROOT:-/workspace/factory-watch}"
PROJ=PVT_kwHOAYEAOs4Bo3vn FIELD=PVTSSF_lAHOAYEAOs4Bo3vnzhnV1ik
declare -A OPT=([Triage]=cdd562ca [Ready]=84a24ea9 [Building]=ed952d58 [Gate]=9cfe6bd1 [Review]=befc9395 [Merge]=240a84ea [Release]=d53e0069 [Blocked]=c59dd1a6 [Done]=037f9c49)
REPOS=(software-factory gh-factory activity-feed line adamsuk)

# GNU date on the box, BSD date on a Mac. The old -d form made this Linux-only.
since_date() {
  date -u -d '-2 days' +%F 2>/dev/null || date -u -v-2d +%F
}

sync_once() {
  local cur; cur=$(gh project item-list 2 --owner adamsuk -L 1000 --format json --jq '.items[]|"\(.content.url)\t\(.id)\t\(."factory status" // "")"') || return
  declare -A ID ST; while IFS=$'\t' read -r u i s; do ID[$u]=$i; ST[$u]=$s; done <<<"$cur"

  # Pass 1: membership, no date window. Process substitution, not a pipe, so
  # the ID map updates in this shell and pass 2 does not re-add.
  local url id
  while read -r url; do
    [[ -n $url ]] || continue
    [[ -z ${ID[$url]:-} ]] || continue
    id=$(gh project item-add 2 --owner adamsuk --url "$url" --format json --jq .id) || continue
    ID[$url]=$id
    echo "$(date -u +%FT%TZ) $url added to board"
  done < <(
    for r in "${REPOS[@]}"; do
      for k in issue pr; do
        gh $k list -R adamsuk/$r --state open -L 500 --json url --jq '.[].url' 2>/dev/null
      done
    done
  )

  # Pass 2: status mirror, 2-day window.
  local since; since=$(since_date)
  local state labels want w
  while IFS=$'\t' read -r url state labels; do
    want=""
    if [[ $labels =~ factory:([a-z]+) ]]; then w=${BASH_REMATCH[1]}; want=${w^}
    elif [[ $url == */pull/* && $state == OPEN ]]; then want=Review
    elif [[ ,$labels, == *,station,* ]]; then want=Triage; fi
    [[ $state == MERGED || ( $state == CLOSED && -n $want ) ]] && want=Done
    [[ -n $want && -n ${OPT[$want]:-} ]] || continue
    [[ $state == CLOSED && -z ${ID[$url]:-} && $url == */pull/* ]] && continue
    id=${ID[$url]:-}
    [[ -n $id ]] || id=$(gh project item-add 2 --owner adamsuk --url "$url" --format json --jq .id) || continue
    [[ ${ST[$url]:-} == "$want" ]] && continue
    gh project item-edit --id "$id" --project-id $PROJ --field-id $FIELD --single-select-option-id "${OPT[$want]}" >/dev/null && echo "$(date -u +%FT%TZ) $url -> $want"
  done < <(
    for r in "${REPOS[@]}"; do
      for k in issue pr; do
        gh $k list -R adamsuk/$r --state all -L 200 --search "updated:>=$since" --json url,state,labels \
          --jq '.[]|"\(.url)\t\(.state)\t\([.labels[].name]|join(","))"' 2>/dev/null
      done
    done
  )
}

while true; do [[ $((10#$(TZ=Europe/London date +%H))) -ge 7 ]] || { sleep 300; continue; }; sync_once >> board-sync.log 2>&1; sleep 180; done
