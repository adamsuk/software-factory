#!/usr/bin/env bash
# Behaviour tests for ir_save_result. Extracts the function from each watcher
# script and runs it in a subshell. Does not start the watcher, call gh, or
# use the network. Fixtures are synthetic. The two copies must agree.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() { printf '%s\n' "FAIL: $*" >&2; exit 1; }
pass() { printf '%s\n' "ok: $*"; }

extract_fn() {
  local src=$1 dest=$2
  awk '
    /^ir_save_result\(\)/ {p=1}
    p {print}
    p && /^\}/ {exit}
  ' "$src" > "$dest"
  [[ -s $dest ]] || fail "empty extract from $src"
  grep -F -q 'ir_save_result()' "$dest" || fail "extract missed ir_save_result in $src"
}

extract_fn "$root/scripts/watcher/watch.sh" "$work/fn-watch.sh"
extract_fn "$root/scripts/watcher/watch.new.sh" "$work/fn-watch.new.sh"
cmp -s "$work/fn-watch.sh" "$work/fn-watch.new.sh" || fail "ir_save_result copies differ"
pass "both ir_save_result copies match"

sha=abc1234deadbeef000000000000000000000000

# $1 case name, $2 grok JSON path. Runs each extracted copy in a subshell.
run_both() {
  local name=$1 grok=$2
  local label dest orig fn result prev
  prev=""
  for label in watch watch.new; do
    dest="$work/${name}.${label}.json"
    orig="$work/${name}.${label}.orig"
    fn="$work/fn-${label}.sh"
    cp "$grok" "$orig"
    (
      # shellcheck disable=SC1090,SC1091
      source "$fn"
      ir_save_result "$grok" "$dest" "$sha"
    )
    [[ -f $grok ]] || fail "$name ($label): grok file missing"
    cmp -s "$orig" "$grok" || fail "$name ($label): grok file bytes changed"
    jq -e --arg sha "$sha" '
      type == "object"
      and .sha == $sha
      and (.at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
    ' "$dest" >/dev/null || fail "$name ($label): result shape"
    result=$(jq -c 'del(.at)' "$dest")
    if [[ -n $prev && $result != "$prev" ]]; then
      fail "$name: copies disagree"
    fi
    prev=$result
  done
}

write_text() {
  local dest=$1 text=$2
  jq -n --arg text "$text" '{structuredOutput: null, text: $text}' > "$dest"
}

assert_verdict() {
  local name=$1 want=$2 got
  got=$(jq -r '.verdict' "$work/${name}.watch.json")
  [[ $got == "$want" ]] || fail "$name: verdict [$got] want [$want]"
}

assert_summary() {
  local name=$1 want=$2 got
  got=$(jq -r '.summary' "$work/${name}.watch.json")
  [[ $got == "$want" ]] || fail "$name: summary [$got] want [$want]"
}

assert_fix() {
  local name=$1 want=$2 got
  got=$(jq -c '.fix' "$work/${name}.watch.json")
  [[ $got == "$want" ]] || fail "$name: fix $got want $want"
}

assert_no_raw() {
  local name=$1
  jq -e 'has("raw") | not' "$work/${name}.watch.json" >/dev/null || fail "$name: unexpected raw"
}

assert_raw() {
  local name=$1 grok=$2
  jq -e --arg raw "$grok" '.raw == $raw' "$work/${name}.watch.json" >/dev/null \
    || fail "$name: raw path"
}

assert_escalate_has() {
  local name=$1 item=$2
  jq -e --arg item "$item" '(.escalate // []) | index($item) != null' \
    "$work/${name}.watch.json" >/dev/null || fail "$name: escalate missing [$item]"
}

first='{"verdict":"FIX","summary":"Reading the work order.","fix":["Review: interim"]}'
second='{"verdict":"PASS","summary":"Meets the criteria.","fix":[]}'
fix_one='{"verdict":"FIX","fix":["Review: missing case"]}'

write_text "$work/concat.grok" "${first}${second}"
run_both concat "$work/concat.grok"
assert_verdict concat PASS
assert_summary concat "Meets the criteria."
assert_fix concat '[]'
assert_no_raw concat
pass "concatenated objects yield the last PASS"

write_text "$work/concat-nl.grok" "${first}"$'\n'"${second}"
run_both concat-nl "$work/concat-nl.grok"
assert_verdict concat-nl PASS
assert_summary concat-nl "Meets the criteria."
assert_no_raw concat-nl
pass "objects separated by a newline yield the last PASS"

write_text "$work/trail.grok" "${fix_one} trailing non-JSON text"
run_both trail "$work/trail.grok"
assert_verdict trail FIX
assert_fix trail '["Review: missing case"]'
assert_no_raw trail
pass "object plus trailing text keeps FIX and the fix item"

write_text "$work/single.grok" '{"verdict":"PASS","summary":"Single object.","fix":[]}'
run_both single "$work/single.grok"
assert_verdict single PASS
assert_summary single "Single object."
assert_no_raw single
pass "one JSON object in .text still yields PASS"

write_text "$work/vline.grok" $'The review found a FIX in passing.\nVERDICT: PASS\n'
run_both vline "$work/vline.grok"
assert_verdict vline PASS
assert_summary vline "Verdict line only; no structured findings."
assert_fix vline '[]'
assert_no_raw vline
pass "final VERDICT: PASS line yields PASS"

write_text "$work/eline.grok" $'This should not PASS on a word.\nESCALATE\n'
run_both eline "$work/eline.grok"
assert_verdict eline ESCALATE
assert_summary eline "Verdict line only; no structured findings."
assert_fix eline '[]'
assert_no_raw eline
pass "final line ESCALATE yields ESCALATE"

write_text "$work/fline.grok" $'VERDICT: FIX\n'
run_both fline "$work/fline.grok"
assert_verdict fline ESCALATE
assert_summary fline "Verdict line only; no structured findings."
assert_escalate_has fline "Verdict FIX listed no findings."
assert_no_raw fline
pass "VERDICT: FIX with no findings becomes ESCALATE"

write_text "$work/sentence.grok" $'The change should PASS review.\nI wrote VERDICT: PASS in the middle of this sentence.\nDo not ESCALATE lightly.\n'
run_both sentence "$work/sentence.grok"
assert_verdict sentence ESCALATE
assert_summary sentence "Independent review output was missing or not parseable."
assert_escalate_has sentence "Review did not return a usable verdict."
assert_raw sentence "$work/sentence.grok"
pass "words inside a sentence are not a verdict"

write_text "$work/none.grok" 'No verdict was returned by the model.'
run_both none "$work/none.grok"
assert_verdict none ESCALATE
assert_summary none "Independent review output was missing or not parseable."
assert_escalate_has none "Review did not return a usable verdict."
assert_raw none "$work/none.grok"
pass "unparseable output escalates and records the grok path"

jq -n --arg text '{"verdict":"FIX","summary":"Later in text.","fix":["Review: later"]}' \
  '{structuredOutput:{verdict:"PASS",summary:"From schema.",fix:[],dismissed:[],escalate:[]}, text:$text}' \
  > "$work/structured.grok"
run_both structured "$work/structured.grok"
assert_verdict structured PASS
assert_summary structured "From schema."
assert_fix structured '[]'
assert_no_raw structured
pass "structuredOutput PASS wins over a later verdict in .text"

pass "all ir verdict parse tests passed"
