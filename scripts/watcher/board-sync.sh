#!/usr/bin/env bash
# Every 3 min (08:00-24:00 London): mirror factory labels onto the Software Factory project board (adamsuk project 2).
# shellcheck disable=SC2164 # || exit would add a failure branch
cd "${FACTORY_WATCH_ROOT:-/workspace/factory-watch}"
PROJ=PVT_kwHOAYEAOs4Bo3vn FIELD=PVTSSF_lAHOAYEAOs4Bo3vnzhnV1ik
declare -A OPT=([Triage]=cdd562ca [Ready]=84a24ea9 [Building]=ed952d58 [Gate]=9cfe6bd1 [Review]=befc9395 [Merge]=240a84ea [Release]=d53e0069 [Blocked]=c59dd1a6 [Done]=037f9c49)
sync_once() {
  local cur; cur=$(gh project item-list 2 --owner adamsuk -L 1000 --format json --jq '.items[]|"\(.content.url)\t\(.id)\t\(."factory status" // "")"') || return
  declare -A ID ST; while IFS=$'\t' read -r u i s; do ID[$u]=$i; ST[$u]=$s; done <<<"$cur"
  local since; since=$(date -u -d '-2 days' +%F)
  for r in software-factory gh-factory activity-feed line adamsuk; do
    for k in issue pr; do
      gh $k list -R adamsuk/$r --state all -L 200 --search "updated:>=$since" --json url,state,labels \
        --jq '.[]|"\(.url)\t\(.state)\t\([.labels[].name]|join(","))"' 2>/dev/null
    done
  done | while IFS=$'\t' read -r url state labels; do
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
  done
}
while true; do [[ $((10#$(TZ=Europe/London date +%H))) -ge 7 ]] || { sleep 300; continue; }; sync_once >> board-sync.log 2>&1; sleep 180; done
