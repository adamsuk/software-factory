#!/usr/bin/env bash
# Brief-shaped test: the foreman's pick cap lives in agents/roles/foreman.md,
# because foreman-orchestrate.sh pick leaves the decision to the agent. ShellCheck covers this file.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
brief="$here/../agents/roles/foreman.md"
reviewer="$here/../agents/roles/reviewer.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

# The Pick step is step 1, which runs until step 2.
pick=$(awk '/^1\. \*\*Pick\.\*\*/{on=1} /^2\. \*\*Resolve/{on=0} on' "$brief")
[[ -n "$pick" ]] || fail "Pick step not found"
grep -q 'Cap: 2 open agent PRs per repo' <<< "$pick" || fail "cap of 2 not stated under Pick"
pickflat=$(tr -s ' \n' '  ' <<< "$pick")
grep -Eq "(^|[.!?*] )Evaluate the cap against the candidate issue's \`Target repo:\`" <<< "$pickflat" || fail "cap is not evaluated against the candidate's Target repo"
! grep -q "PR's own repo (the repo the branch" <<< "$pickflat" || fail "cap still counts against the PR's own repo"
grep -q 'branch-only' <<< "$pickflat" || fail "cap does not count branch-only in-flight entries"
grep -q 'new' <<< "$pick" || fail "cap does not say it applies to new issues"
echo "ok: foreman Pick states the cap of 2"

# It must appear once, not also elsewhere in the brief.
[[ $(grep -c 'Cap: 2 open agent PRs' "$brief") -eq 1 ]] || fail "cap stated more than once"
echo "ok: cap stated once"

grep -q 'station 05 Review' "$reviewer" || fail "reviewer brief lacks station header"
grep -q '\*\*Takes in\*\*' "$reviewer" || fail "reviewer lacks takes in"
grep -q '\*\*Hands on\*\*' "$reviewer" || fail "reviewer lacks hands on"
station=$(awk '/^## Station/{on=1; next} /^## /{on=0} on' "$reviewer")
grep -q 'L/XL' <<< "$station" || fail "reviewer header does not mention L/XL escalation"
# L/XL must route to blocked via ESCALATE, not to merge via PASS.
grep -Eq 'ESCALATE, including an L/XL' <<< "${station//$'\n'/ }" || fail "reviewer header does not route L/XL via ESCALATE"
stationflat="${station//$'\n'/ }"
grep -Eq 'factory:blocked. \(ESCALATE, including an L/XL' <<< "$stationflat" || fail "reviewer header does not send ESCALATE/L-XL to factory:blocked"
grep -q 'linked issue' <<< "$stationflat" || fail "reviewer header does not attribute factory:review to the linked issue"
echo "ok: reviewer station header"

# In-flight issues must not be routed back through Build (step 4); the cap
# text must say steps 6-7, not a range that includes Build.
grep -q 'stay on steps 6-7' <<< "$pick" || fail "cap does not keep in-flight issues on steps 6-7 only"
! grep -q 'steps 2-7' <<< "$pick" || fail "cap still claims steps 2-7"
echo "ok: in-flight issues are not routed back through Build"

# Step 6 (Independent verdict) must also carry the L/XL rule, not just the header.
verdict=$(awk '/^6\. \*\*Independent verdict\.\*\*/{on=1} /^## Outputs/{on=0} on' "$reviewer")
[[ -n "$verdict" ]] || fail "Independent verdict step not found"
grep -q 'L/XL' <<< "$verdict" || fail "Independent verdict step does not mention L/XL"
grep -q 'L/XL change is reported as ESCALATE, not PASS' <<< "$verdict" || fail "Independent verdict step does not route L/XL via ESCALATE"
! grep -q 'or an L/XL one, goes to Scott' <<< "$verdict" || fail "Independent verdict step still routes L/XL via PASS"
# shellcheck disable=SC2016  # literal backticked text, not expansion
grep -Fq 'ESCALATE both set `factory:blocked`' <<< "${verdict//$'\n'/ }" || fail "Independent verdict step does not route ESCALATE to factory:blocked"
grep -Fq 'ESCALATE takes precedence over FIX for an L/XL change' <<< "${verdict//$'\n'/ }" || fail "Independent verdict step does not say ESCALATE wins over FIX for L/XL"
echo "ok: Independent verdict step states the L/XL rule"

# Round 7: label-only in-flight entries count, and a capped candidate does not
# stop the scan.
# shellcheck disable=SC2016  # literal backticked text, not expansion
grep -Fq 'an issue labelled `factory:building`' <<< "$pickflat" || fail "cap does not count factory:building as in flight"
grep -Fq 'continue scanning in age order for the next-oldest eligible candidate' <<< "$pickflat" || fail "Pick does not scan past a capped candidate"
grep -Fq 'only if no later candidate passes the cap' <<< "$pickflat" || fail "capacity-full report is not conditional on no later candidate"
echo "ok: factory:building counts and scan continues past a capped candidate"

grep -Fq -- '--should-fix N' "$reviewer" || fail "reviewer brief does not document --should-fix"
grep -Fq -- '--should-fix' "$here/../stations/github-writes.md" || fail "github-writes does not document --should-fix"
echo "ok: --should-fix documented"

# Round 9: the cap counts unique issues, not one per matching artifact.
# shellcheck disable=SC2016  # literal backticked text, not expansion
grep -Fq 'The cap counts unique `(Target repo, issue)` pairs, not one count per matching artifact' <<< "$pickflat" || fail "cap does not count unique issues"
echo "ok: cap counts unique (Target repo, issue) pairs"
