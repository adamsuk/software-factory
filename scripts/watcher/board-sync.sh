#!/usr/bin/env bash
# Every 3 min (07:00-24:00 London): keep the factory project board in step
# with the factory labels. `--once` runs one sync now and exits.
#
# Configuration, all required; with any unset this prints "board sync not
# configured" and exits 0:
#   FACTORY_BOARD_OWNER       project owner (user or org login)
#   FACTORY_BOARD_NUMBER      project number
#   FACTORY_BOARD_PROJECT_ID  project node id
#   FACTORY_BOARD_FIELD_ID    node id of the `factory status` single-select field
#   FACTORY_BOARD_OPTIONS     JSON object: status name (Triage, Ready, Building,
#                             Gate, Review, Merge, Release, Blocked, Done) to option id
# The repos synced are FACTORY_REPOS (default FACTORY_HOME_REPO).
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
# >>> factory env: the shared settings live in factory-env.sh, beside this script.
factory_env_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/factory-env.sh"
if [[ ! -r $factory_env_file ]]; then
  printf '%s: cannot read %s (factory-env.sh must sit beside the watcher scripts)\n' "${BASH_SOURCE[0]##*/}" "$factory_env_file" >&2
  exit 1
fi
# shellcheck source=scripts/watcher/factory-env.sh
source "$factory_env_file"
# <<< factory env
for _v in FACTORY_BOARD_OWNER FACTORY_BOARD_NUMBER FACTORY_BOARD_PROJECT_ID FACTORY_BOARD_FIELD_ID FACTORY_BOARD_OPTIONS; do
  [[ -n ${!_v:-} ]] || { echo "board sync not configured (${_v} is unset)"; exit 0; }
done
OWNER=$FACTORY_BOARD_OWNER NUMBER=$FACTORY_BOARD_NUMBER
PROJ=$FACTORY_BOARD_PROJECT_ID FIELD=$FACTORY_BOARD_FIELD_ID
declare -A OPT=()
_opts=$(jq -r 'if type == "object" then to_entries[] | "\(.key)\t\(.value)" else error("not an object") end' <<<"$FACTORY_BOARD_OPTIONS" 2>/dev/null) \
  || { echo "FACTORY_BOARD_OPTIONS is not a JSON object" >&2; exit 2; }
while IFS=$'\t' read -r _k _id; do [[ -n $_k ]] && OPT[$_k]=$_id; done <<<"$_opts"
factory_resolve_repos || { echo "no repos: set FACTORY_REPOS or FACTORY_HOME_REPO" >&2; exit 2; }
read -r -a REPOS <<<"$FACTORY_REPOS"
# shellcheck disable=SC2164 # || exit would add a failure branch
cd "$FACTORY_WATCH_ROOT"

# Needs bash 4 or newer for `declare -A` and `${w^}`. Those are runtime
# features, so bash 3.2 parses this file without complaint and then fails on it:
# macOS's /bin/bash is 3.2, while a Homebrew bash on PATH is fine. Run it with
# the bash on PATH, not /bin/bash.
#
# GNU date on the box, BSD date on a Mac. The old -d form made the date call
# Linux-only; the rest of the script's portability is the bash version above.
since_date() {
  date -u -d '-2 days' +%F 2>/dev/null || date -u -v-2d +%F
}

sync_once() {
  local cur; cur=$(gh project item-list "$NUMBER" --owner "$OWNER" -L 1000 --format json --jq '.items[]|"\(.content.url)\t\(.id)\t\(."factory status" // "")"') || return
  declare -A ID ST; while IFS=$'\t' read -r u i s; do ID[$u]=$i; ST[$u]=$s; done <<<"$cur"

  # Pass 1: membership, no date window. Process substitution, not a pipe, so
  # the ID map updates in this shell and pass 2 does not re-add.
  local url id
  while read -r url; do
    [[ -n $url ]] || continue
    [[ -z ${ID[$url]:-} ]] || continue
    id=$(gh project item-add "$NUMBER" --owner "$OWNER" --url "$url" --format json --jq .id) || continue
    ID[$url]=$id
    echo "$(date -u +%FT%TZ) $url added to board"
  done < <(
    for r in "${REPOS[@]}"; do
      for k in issue pr; do
        gh $k list -R "$r" --state open -L 500 --json url --jq '.[].url' 2>/dev/null
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
    [[ -n $id ]] || id=$(gh project item-add "$NUMBER" --owner "$OWNER" --url "$url" --format json --jq .id) || continue
    [[ ${ST[$url]:-} == "$want" ]] && continue
    gh project item-edit --id "$id" --project-id "$PROJ" --field-id "$FIELD" --single-select-option-id "${OPT[$want]}" >/dev/null && echo "$(date -u +%FT%TZ) $url -> $want"
  done < <(
    for r in "${REPOS[@]}"; do
      for k in issue pr; do
        gh $k list -R "$r" --state all -L 200 --search "updated:>=$since" --json url,state,labels \
          --jq '.[]|"\(.url)\t\(.state)\t\([.labels[].name]|join(","))"' 2>/dev/null
      done
    done
  )
}

if [[ ${1:-} == --once ]]; then sync_once; exit 0; fi
while true; do [[ $((10#$(TZ=Europe/London date +%H))) -ge 7 ]] || { sleep 300; continue; }; sync_once >> board-sync.log 2>&1; sleep 180; done
