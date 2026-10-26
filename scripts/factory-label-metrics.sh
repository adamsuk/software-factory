#!/usr/bin/env bash
# Read-only counts of the nine factory:* status labels from issue events.
#
# Usage: scripts/factory-label-metrics.sh --repo <owner/name> --since YYYY-MM-DD --until YYYY-MM-DD
#
# --since is inclusive and --until is exclusive, both UTC midnights.
# Exit 0 prints one markdown document on stdout.
# Exit 2: a flag is missing or an argument is invalid. No gh call, no stdout.
# Exit 7: a gh command failed, or the issue list has 200 objects. No stdout.
# On success the only gh calls are `gh issue list` and one `gh api` events
# request per returned issue. A full page of 200 is not followed by events calls.
set -euo pipefail

export TZ=UTC
export LC_ALL=C

labels=(
  factory:triage
  factory:ready
  factory:building
  factory:gate
  factory:review
  factory:merge
  factory:release
  factory:done
  factory:blocked
)

die_usage() { exit 2; }
die_data() { exit 7; }

valid_date() {
  local raw=$1
  local norm
  [[ "$raw" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
  norm=$(date -u -d "$raw" +%Y-%m-%d 2>/dev/null) || return 1
  [[ "$norm" == "$raw" ]]
}

station_id() {
  local i
  for i in "${!labels[@]}"; do
    if [[ "${labels[i]}" == "$1" ]]; then
      printf '%s' "$i"
      return 0
    fi
  done
  return 1
}

# Latest labeled epoch in $1 that is <= $2. Empty if there is no such add.
latest_at_or_before() {
  local file=$1
  local limit=$2
  local line best
  best=
  [[ "$limit" =~ ^[0-9]+$ ]] || return 0
  if [[ -s "$file" ]]; then
    while IFS= read -r line; do
      [[ "$line" =~ ^[0-9]+$ ]] || continue
      if (( line <= limit )) && { [[ -z "$best" ]] || (( line > best )); }; then
        best=$line
      fi
    done < "$file"
  fi
  printf '%s' "$best"
}

# Median of whole-second durations in $1, rounded half away from zero to
# one decimal hour. No durations prints n/a.
format_median() {
  local file=$1
  local n num den tenths a b sorted
  local -a vals
  vals=()
  if [[ ! -s "$file" ]]; then
    printf 'n/a'
    return 0
  fi
  sorted=$(sort -n "$file") || die_data
  mapfile -t vals <<< "$sorted"
  n=${#vals[@]}
  if (( n == 0 )); then
    printf 'n/a'
    return 0
  fi
  if (( n % 2 == 1 )); then
    num=${vals[$((n / 2))]}
    den=3600
  else
    a=${vals[$((n / 2 - 1))]}
    b=${vals[$((n / 2))]}
    num=$((a + b))
    den=7200
  fi
  # tenths = round_half_away_from_zero(num / den * 10)
  tenths=$(( (num * 10 + den / 2) / den ))
  printf '%d.%d' $((tenths / 10)) $((tenths % 10))
}

record_issue() {
  local events_file=$1
  local kind tsv created event name id epoch best dur norm
  kind=$(jq -r 'type' "$events_file") || die_data
  [[ "$kind" == "array" ]] || die_data
  tsv=$(jq -r '
    .[]
    | select(.event == "labeled" or .event == "unlabeled")
    | select(.created_at | type == "string")
    | select(.label.name | type == "string")
    | [.created_at, .event, .label.name]
    | @tsv
  ' "$events_file") || die_data

  for id in "${!labels[@]}"; do
    : > "$work/add_$id"
  done
  norm=$work/norm.tsv
  : > "$norm"
  if [[ -n "$tsv" ]]; then
    while IFS=$'\t' read -r created event name; do
      id=$(station_id "$name") || continue
      epoch=$(date -u -d "$created" +%s 2>/dev/null) || die_data
      printf '%s\t%s\t%s\n' "$epoch" "$event" "$id" >> "$norm"
    done <<< "$tsv"
  fi

  while IFS=$'\t' read -r epoch event id; do
    [[ -n "$epoch" ]] || continue
    if [[ "$event" == "labeled" ]]; then
      printf '%s\n' "$epoch" >> "$work/add_$id"
    fi
  done < "$norm"

  while IFS=$'\t' read -r epoch event id; do
    [[ -n "$epoch" ]] || continue
    if (( epoch < since_epoch || epoch >= until_epoch )); then
      continue
    fi
    if [[ "$event" == "labeled" ]]; then
      in_n[id]=$((in_n[id] + 1))
    elif [[ "$event" == "unlabeled" ]]; then
      out_n[id]=$((out_n[id] + 1))
      best=$(latest_at_or_before "$work/add_$id" "$epoch")
      if [[ -n "$best" ]]; then
        dur=$((epoch - best))
        printf '%s\n' "$dur" >> "$work/dur_$id"
      fi
    fi
  done < "$norm"
}

repo=
since=
until=

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo|--since|--until)
      [[ $# -ge 2 ]] || die_usage
      case "$1" in
        --repo)
          [[ -z "$repo" ]] || die_usage
          repo=$2
          ;;
        --since)
          [[ -z "$since" ]] || die_usage
          since=$2
          ;;
        --until)
          [[ -z "$until" ]] || die_usage
          until=$2
          ;;
      esac
      shift 2
      ;;
    *)
      die_usage
      ;;
  esac
done

[[ -n "$repo" && -n "$since" && -n "$until" ]] || die_usage
[[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die_usage
valid_date "$since" || die_usage
valid_date "$until" || die_usage

since_epoch=$(date -u -d "$since" +%s 2>/dev/null) || die_usage
until_epoch=$(date -u -d "$until" +%s 2>/dev/null) || die_usage
[[ "$since_epoch" -lt "$until_epoch" ]] || die_usage

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if ! gh issue list --repo "$repo" --state all --limit 200 --search "updated:>=${since}" --json number > "$work/list.json"; then
  die_data
fi

count=$(jq -r 'if type == "array" then length else "bad" end' "$work/list.json") || die_data
[[ "$count" =~ ^[0-9]+$ ]] || die_data
# 200 is the page cap: the list may be truncated, so do not read events.
if (( count >= 200 )); then
  die_data
fi

declare -a numbers
numbers=()
if (( count > 0 )); then
  numbers_text=$(jq -r '.[].number' "$work/list.json") || die_data
  sorted_numbers=$(printf '%s\n' "$numbers_text" | sort -n) || die_data
  while IFS= read -r num; do
    [[ -n "$num" ]] || continue
    [[ "$num" =~ ^[0-9]+$ ]] || die_data
    numbers+=("$num")
  done <<< "$sorted_numbers"
fi

declare -a in_n out_n
for i in "${!labels[@]}"; do
  in_n[i]=0
  out_n[i]=0
  : > "$work/dur_$i"
done

if (( ${#numbers[@]} > 0 )); then
  for n in "${numbers[@]}"; do
    if ! gh api --paginate "repos/${repo}/issues/${n}/events" > "$work/events.json"; then
      die_data
    fi
    record_issue "$work/events.json"
  done
fi

printf '# Factory label metrics\n'
printf 'repo: %s\n' "$repo"
printf 'since: %s\n' "$since"
printf 'until: %s\n' "$until"
printf '\n'
printf '| station | in | out | median lead time hours |\n'
printf '| --- | --- | --- | --- |\n'
for i in "${!labels[@]}"; do
  printf '| %s | %s | %s | %s |\n' \
    "${labels[i]}" "${in_n[i]}" "${out_n[i]}" "$(format_median "$work/dur_$i")"
done
