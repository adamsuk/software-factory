#!/usr/bin/env bash
# Read-only factory pull request metrics for one UTC date window.
#
# Usage: scripts/factory-pr-metrics.sh --repo <owner/name> --since YYYY-MM-DD --until YYYY-MM-DD
#
# Exit 2: a flag is missing, or the repo or either date is invalid, or since
# is not strictly before until. No gh call and no stdout.
# Exit 7: a gh read failed, its output is not a JSON list, or a list has
# 200 items (the request cap, so the totals would be incomplete). No stdout.
# --since is inclusive and --until is exclusive. Both dates are UTC midnights.
# The only gh calls are the two `gh pr list` reads below.
# Station 08 matches two whole-line shapes: `api_equiv_usd:` then a
# non-negative number with at most two decimal places, and `attempt:` then
# `1`, `2`, or `3`.
set -euo pipefail

export LC_ALL=C

repo=""
since=""
until=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo|--since|--until)
      [[ $# -ge 2 ]] || exit 2
      case "$1" in
        --repo)
          [[ -z "$repo" ]] || exit 2
          repo=$2
          ;;
        --since)
          [[ -z "$since" ]] || exit 2
          since=$2
          ;;
        --until)
          [[ -z "$until" ]] || exit 2
          until=$2
          ;;
      esac
      shift 2
      ;;
    *)
      exit 2
      ;;
  esac
done

[[ -n "$repo" && -n "$since" && -n "$until" ]] || exit 2
[[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || exit 2

# YYYY-MM-DD, and GNU date prints that same day back. Rejects 2026-02-31.
valid_utc_date() {
  local raw=$1
  local back
  [[ "$raw" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
  back=$(date -u -d "$raw" +%Y-%m-%d 2>/dev/null) || return 1
  [[ "$back" == "$raw" ]]
}

valid_utc_date "$since" || exit 2
valid_utc_date "$until" || exit 2
# LC_ALL=C makes this a byte compare. Valid ISO dates sort in calendar order.
[[ "$since" < "$until" ]] || exit 2

# 0 when stdin is a JSON list shorter than the 200-item gh cap.
require_short_list() {
  local cap_status=0
  python3 -c 'import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(3)
if not isinstance(data, list) or len(data) >= 200:
    raise SystemExit(3)
' <"$1" || cap_status=$?
  [[ "$cap_status" -eq 0 ]]
}

all_file=$(mktemp)
open_file=$(mktemp)
trap 'rm -f "$all_file" "$open_file"' EXIT

if ! gh pr list \
  --repo "$repo" \
  --state all \
  --limit 200 \
  --search "updated:>=${since}" \
  --json number,body,state,headRefName,updatedAt,reviews \
  >"$all_file" 2>/dev/null; then
  exit 7
fi

require_short_list "$all_file" || exit 7

if ! gh pr list \
  --repo "$repo" \
  --state open \
  --limit 200 \
  --json number,headRefName \
  >"$open_file" 2>/dev/null; then
  exit 7
fi

require_short_list "$open_file" || exit 7

python3 - "$all_file" "$open_file" "$repo" "$since" "$until" << 'PY' || exit 7
import json
import re
import sys
from datetime import datetime, timezone

all_path, open_path, repo, since, until = sys.argv[1:6]

COST_RE = re.compile(r"^api_equiv_usd: ([0-9]+)(?:\.([0-9]{1,2}))?$")
ATTEMPT_RE = re.compile(r"^attempt: ([123])$")
TESTS_PASS = "tests: pass"
REVIEW_STATES = {"APPROVED", "CHANGES_REQUESTED", "COMMENTED"}
INSTANT_RE = re.compile(
    r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T"
    r"[0-9]{2}:[0-9]{2}:[0-9]{2}"
    r"(?:\.[0-9]+)?"
    r"(?:Z|[+-][0-9]{2}:[0-9]{2})$"
)


def utc_midnight(iso_day):
    return datetime(
        int(iso_day[0:4]),
        int(iso_day[5:7]),
        int(iso_day[8:10]),
        tzinfo=timezone.utc,
    )


since_dt = utc_midnight(since)
until_dt = utc_midnight(until)


def parse_instant(value):
    if not isinstance(value, str) or INSTANT_RE.fullmatch(value) is None:
        return None
    text = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return None
    return parsed.astimezone(timezone.utc)


def in_window(instant):
    return instant is not None and since_dt <= instant < until_dt


def iter_lines(body):
    if not isinstance(body, str):
        return
    for raw in body.split("\n"):
        if raw.endswith("\r"):
            raw = raw[:-1]
        yield raw


def to_cents(whole, frac):
    cents = int(whole) * 100
    if frac is None:
        return cents
    if len(frac) == 1:
        return cents + int(frac) * 10
    return cents + int(frac)


def format_cents(cents):
    return f"{cents // 100}.{cents % 100:02d}"


def main():
    with open(all_path, encoding="utf-8") as handle:
        kept_source = json.load(handle)
    with open(open_path, encoding="utf-8") as handle:
        open_source = json.load(handle)
    if not isinstance(kept_source, list) or not isinstance(open_source, list):
        raise SystemExit(7)

    total_cents = 0
    scored = 0
    green = 0
    fix_attempts = 0
    review_rounds = 0

    for pr in kept_source:
        if not isinstance(pr, dict):
            continue
        if not in_window(parse_instant(pr.get("updatedAt"))):
            continue
        got_cost = False
        got_attempt = False
        got_tests = False
        attempt_n = None
        passed = False
        for line in iter_lines(pr.get("body")):
            if not got_cost:
                matched = COST_RE.fullmatch(line)
                if matched is not None:
                    total_cents += to_cents(matched.group(1), matched.group(2))
                    got_cost = True
            if not got_attempt:
                matched = ATTEMPT_RE.fullmatch(line)
                if matched is not None:
                    attempt_n = int(matched.group(1))
                    got_attempt = True
            if not got_tests and line == TESTS_PASS:
                passed = True
                got_tests = True
        if got_attempt:
            scored += 1
            fix_attempts += attempt_n - 1
            if attempt_n == 1 and passed:
                green += 1
        reviews = pr.get("reviews")
        if not isinstance(reviews, list):
            continue
        for review in reviews:
            if not isinstance(review, dict):
                continue
            if review.get("state") not in REVIEW_STATES:
                continue
            if in_window(parse_instant(review.get("submittedAt"))):
                review_rounds += 1

    open_agent = 0
    for pr in open_source:
        if not isinstance(pr, dict):
            continue
        name = pr.get("headRefName")
        if isinstance(name, str) and name.startswith("factory/"):
            open_agent += 1

    if scored == 0:
        first_green = "n/a"
    else:
        first_green = f"{green}/{scored}"

    sys.stdout.write(
        "# Factory pull request metrics\n"
        f"repo: {repo}\n"
        f"since: {since}\n"
        f"until: {until}\n"
        "\n"
        "| metric | value |\n"
        "| --- | --- |\n"
        f"| grok cost usd | {format_cents(total_cents)} |\n"
        f"| first-time-green | {first_green} |\n"
        f"| fix attempts | {fix_attempts} |\n"
        f"| review rounds | {review_rounds} |\n"
        f"| open agent prs | {open_agent} |\n"
    )


try:
    main()
except SystemExit:
    raise
except Exception:
    raise SystemExit(7)
PY
