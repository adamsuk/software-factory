#!/usr/bin/env bash
# Read-only factory delivery metrics for one UTC date window.
#
# Usage: scripts/factory-delivery-metrics.sh --repo OWNER/NAME \
#   --since YYYY-MM-DD --until YYYY-MM-DD --ledger PATH \
#   --required-check NAME [--required-check NAME ...]
#
# --since is inclusive and --until is exclusive. Both dates are UTC midnights.
# Exit 2: a flag is missing or an argument is invalid. No gh call and no stdout.
# Exit 7: a gh read failed, the merged list is at the 200 cap, a commit or
# check-run payload is unusable, or the ledger exists but its header is not
# the watcher columns. No stdout.
# Exit 0 prints the delivery markdown. The only gh calls are reads.
#
# Change failure rate uses merged pull requests whose head matches
# factory/<digits>- . A failure is a revert or a factory follow-up fix merged
# later and at most 7 times 24 hours after that merge. The read includes
# merges up to 7 days after --until.
# Rework and cost read the ledger. Rework does not filter on repo. Cost does.
# Recovery walks default-branch commits from 7 days before --since up to
# --until. Each red commit is measured to the next green commit. Hours are
# the sum of the intervals whose failing check completed in the window and
# whose green checks completed before --until.
set -euo pipefail

export LC_ALL=C
export TZ=UTC

repo=""
since=""
until=""
ledger=""
required=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo|--since|--until|--ledger|--required-check)
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
        --ledger)
          [[ -z "$ledger" ]] || exit 2
          ledger=$2
          ;;
        --required-check)
          [[ "$2" =~ [^[:space:]] ]] || exit 2
          required+=("$2")
          ;;
      esac
      shift 2
      ;;
    *)
      exit 2
      ;;
  esac
done

[[ -n "$repo" && -n "$since" && -n "$until" && -n "$ledger" ]] || exit 2
[[ ${#required[@]} -gt 0 ]] || exit 2
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

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/checks"

search_from=$(date -u -d "$since - 1 day" +%Y-%m-%d 2>/dev/null) || exit 7
search_to=$(date -u -d "$until + 7 days" +%Y-%m-%d 2>/dev/null) || exit 7
lookback=$(date -u -d "$since - 7 days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || exit 7
until_iso="${until}T00:00:00Z"

if ! gh pr list \
  --repo "$repo" \
  --state merged \
  --limit 200 \
  --search "merged:${search_from}..${search_to}" \
  --json number,title,body,headRefName,mergedAt \
  >"$work/prs.json" 2>/dev/null; then
  exit 7
fi

# A full page of 200 is the request cap, so the totals would be incomplete.
python3 - "$work/prs.json" << 'PY' || exit 7
import json
import sys

try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    raise SystemExit(7)
if not isinstance(data, list) or len(data) >= 200:
    raise SystemExit(7)
PY

if ! gh api "repos/${repo}" --jq .default_branch >"$work/branch.txt" 2>/dev/null; then
  exit 7
fi
branch=$(<"$work/branch.txt")
branch=${branch//$'\r'/}
branch=${branch//$'\n'/}
[[ -n "$branch" ]] || exit 7

branch_q=$(python3 -c 'import urllib.parse, sys; sys.stdout.write(urllib.parse.quote(sys.argv[1], safe=""))' "$branch") || exit 7

# --slurp keeps every page inside one JSON array. A page is itself an array.
if ! gh api --paginate --slurp \
  "repos/${repo}/commits?sha=${branch_q}&since=${lookback}&until=${until_iso}&per_page=100" \
  >"$work/commits.json" 2>/dev/null; then
  exit 7
fi

python3 - "$work/commits.json" "$work/shas.txt" << 'PY' || exit 7
import json
import sys

def flatten_pages(data):
    if not isinstance(data, list):
        raise SystemExit(7)
    if data and all(isinstance(page, list) for page in data):
        flat = []
        for page in data:
            flat.extend(page)
        return flat
    return data

src, dest = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(src, encoding="utf-8"))
except Exception:
    raise SystemExit(7)
data = flatten_pages(data)
seen = []
for item in data:
    if not isinstance(item, dict):
        raise SystemExit(7)
    sha = item.get("sha")
    if not isinstance(sha, str) or len(sha) != 40 or any(ch not in "0123456789abcdef" for ch in sha):
        raise SystemExit(7)
    if sha not in seen:
        seen.append(sha)
with open(dest, "w", encoding="utf-8") as handle:
    for sha in seen:
        handle.write(sha + "\n")
PY

while IFS= read -r sha || [[ -n "$sha" ]]; do
  [[ -n "$sha" ]] || continue
  if ! gh api --paginate --slurp \
    "repos/${repo}/commits/${sha}/check-runs?per_page=100" \
    >"$work/checks/${sha}.json" 2>/dev/null; then
    exit 7
  fi
done <"$work/shas.txt"

: >"$work/required.txt"
for name in "${required[@]}"; do
  printf '%s\n' "$name" >>"$work/required.txt"
done

python3 - "$work/prs.json" "$work/commits.json" "$work/checks" "$work/required.txt" \
  "$ledger" "$repo" "$since" "$until" << 'PY' || exit 7
import csv
import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone
from decimal import Decimal, ROUND_HALF_UP

prs_path, commits_path, checks_dir, required_path, ledger_path, repo, since, until = sys.argv[1:9]

HEADER = [
    "date_utc",
    "kind",
    "repo",
    "issue_or_pr",
    "grok_sessions",
    "api_equiv_usd",
    "result",
]
FACTORY_RE = re.compile(r"^factory/([0-9]+)-")
INSTANT_RE = re.compile(
    r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T"
    r"[0-9]{2}:[0-9]{2}:[0-9]{2}"
    r"(?:\.[0-9]+)?"
    r"(?:Z|[+-][0-9]{2}:[0-9]{2})$"
)
SEVEN = timedelta(days=7)
COST_RE = re.compile(r"^[0-9]+(?:\.[0-9]+)?$")


def utc_midnight(iso_day):
    return datetime(
        int(iso_day[0:4]),
        int(iso_day[5:7]),
        int(iso_day[8:10]),
        tzinfo=timezone.utc,
    )


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


def format_decimal(value, places):
    quantum = Decimal(1).scaleb(-places)
    rounded = value.quantize(quantum, rounding=ROUND_HALF_UP)
    return f"{rounded:.{places}f}"


def decimal_seconds(start, end):
    delta = end - start
    micros = (
        delta.days * 86400 * 1_000_000
        + delta.seconds * 1_000_000
        + delta.microseconds
    )
    return Decimal(micros) / Decimal(1_000_000)


def load_json(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except Exception:
        raise SystemExit(7)


def flatten_pages(data):
    if not isinstance(data, list):
        raise SystemExit(7)
    if data and all(isinstance(page, list) for page in data):
        flat = []
        for page in data:
            flat.extend(page)
        return flat
    return data


def load_required():
    names = []
    with open(required_path, encoding="utf-8") as handle:
        for line in handle:
            name = line[:-1] if line.endswith("\n") else line
            if name and name not in names:
                names.append(name)
    if not names:
        raise SystemExit(7)
    return names


def load_ledger(path):
    if not os.path.exists(path):
        return None
    if not os.path.isfile(path):
        raise SystemExit(7)
    try:
        handle = open(path, encoding="utf-8", newline="")
    except OSError:
        raise SystemExit(7)
    with handle:
        if handle.read(1) == "":
            return []
        handle.seek(0)
        reader = csv.DictReader(handle)
        names = reader.fieldnames
        if names is None:
            return []
        cleaned = [(name or "").strip() for name in names]
        if cleaned != HEADER:
            raise SystemExit(7)
        return list(reader)


def text_of(value):
    return value if isinstance(value, str) else ""


def contains_token(text, needle):
    start = 0
    while True:
        found = text.find(needle, start)
        if found < 0:
            return False
        end = found + len(needle)
        if end == len(text) or not text[end].isdigit():
            return True
        start = found + 1


def is_revert(title, body, number):
    needles = (f"Reverts #{number}", f"Reverts {repo}#{number}")
    for text in (text_of(title), text_of(body)):
        for needle in needles:
            if contains_token(text, needle):
                return True
    return False


def mentions(title, body, number):
    # "#<n>" matches inside "other/repo#<n>" too. A longer number does not.
    needles = (f"#{number}", f"{repo}#{number}")
    for text in (text_of(title), text_of(body)):
        for needle in needles:
            if contains_token(text, needle):
                return True
    return False


def is_fix_title(title):
    folded = text_of(title).casefold()
    return folded.startswith("fix:") or folded.startswith("fix ") or "hotfix" in folded


def is_followup(other, number):
    ref = other.get("headRefName")
    if not isinstance(ref, str) or not ref.startswith("factory/"):
        return False
    if not is_fix_title(other.get("title")):
        return False
    return mentions(other.get("title"), other.get("body"), number)


def ids_of(pr, issue):
    return {str(pr["number"]), issue}


def row_id(row):
    raw = row.get("issue_or_pr")
    if raw is None:
        return ""
    return str(raw).strip()


def count_fixes(rows, pr, issue):
    wanted = ids_of(pr, issue)
    count = 0
    for row in rows:
        if (row.get("kind") or "") != "fix":
            continue
        if row_id(row) in wanted:
            count += 1
    return count


def parse_cost(raw):
    if raw is None:
        return None
    text = str(raw).strip()
    if COST_RE.fullmatch(text) is None:
        return None
    return Decimal(text)


def sum_cost(rows, pr, issue):
    wanted = ids_of(pr, issue)
    total = Decimal(0)
    any_numeric = False
    for row in rows:
        if (row.get("repo") or "").strip() != repo:
            continue
        if row_id(row) not in wanted:
            continue
        cost = parse_cost(row.get("api_equiv_usd"))
        if cost is None:
            continue
        any_numeric = True
        total += cost
    return total, any_numeric


def commit_when(item):
    commit = item.get("commit")
    if not isinstance(commit, dict):
        raise SystemExit(7)
    committer = commit.get("committer")
    if not isinstance(committer, dict):
        raise SystemExit(7)
    when = parse_instant(committer.get("date"))
    if when is None:
        raise SystemExit(7)
    return when


def load_check_runs(sha):
    data = load_json(os.path.join(checks_dir, sha + ".json"))
    if not isinstance(data, list):
        raise SystemExit(7)
    runs = []
    for page in data:
        if not isinstance(page, dict):
            raise SystemExit(7)
        chunk = page.get("check_runs", [])
        if chunk is None:
            chunk = []
        if not isinstance(chunk, list):
            raise SystemExit(7)
        for run in chunk:
            if not isinstance(run, dict):
                raise SystemExit(7)
            runs.append(run)
    return runs


def choose_runs(runs, names):
    by_name = {name: [] for name in names}
    for run in runs:
        name = run.get("name")
        if isinstance(name, str) and name in by_name:
            by_name[name].append(run)
    chosen = {}
    for name, group in by_name.items():
        if not group:
            continue
        chosen[name] = max(group, key=run_sort_key)
    return chosen


def run_sort_key(run):
    when = parse_instant(run.get("completed_at"))
    ident = run.get("id")
    if isinstance(ident, bool) or not isinstance(ident, int):
        ident = 0
    if when is None:
        return (0, datetime.min.replace(tzinfo=timezone.utc), ident)
    return (1, when, ident)


def classify(runs, names):
    chosen = choose_runs(runs, names)
    conclusions = []
    failure_times = []
    success_times = []
    for name in names:
        run = chosen.get(name)
        if run is None:
            conclusions.append(None)
            continue
        conclusion = run.get("conclusion")
        conclusions.append(conclusion)
        when = parse_instant(run.get("completed_at"))
        if conclusion == "failure" and when is not None:
            failure_times.append(when)
        if conclusion == "success" and when is not None:
            success_times.append(when)
    if any(item == "failure" for item in conclusions):
        if not failure_times:
            return "red", None
        return "red", min(failure_times)
    if conclusions and all(item == "success" for item in conclusions):
        if len(success_times) != len(names):
            return "green", None
        return "green", max(success_times)
    return "neither", None


def main():
    since_dt = utc_midnight(since)
    until_dt = utc_midnight(until)
    until_plus = until_dt + SEVEN
    names = load_required()
    ledger = load_ledger(ledger_path)

    prs = load_json(prs_path)
    if not isinstance(prs, list) or len(prs) >= 200:
        raise SystemExit(7)

    pool = []
    for pr in prs:
        if not isinstance(pr, dict):
            raise SystemExit(7)
        number = pr.get("number")
        if isinstance(number, bool) or not isinstance(number, int):
            raise SystemExit(7)
        raw_merged = pr.get("mergedAt")
        if raw_merged is None:
            continue
        merged = parse_instant(raw_merged)
        if merged is None:
            raise SystemExit(7)
        if since_dt <= merged < until_plus:
            pool.append(pr)

    denominator = []
    for pr in pool:
        merged = parse_instant(pr.get("mergedAt"))
        if merged is None or not (since_dt <= merged < until_dt):
            continue
        ref = pr.get("headRefName")
        if not isinstance(ref, str):
            continue
        matched = FACTORY_RE.match(ref)
        if matched is None:
            continue
        denominator.append(pr)

    if not denominator:
        failure_rate = "n/a"
    else:
        failures = 0
        for pr in denominator:
            merged = parse_instant(pr.get("mergedAt"))
            number = str(pr["number"])
            failed = False
            for other in pool:
                if other is pr:
                    continue
                other_merged = parse_instant(other.get("mergedAt"))
                if other_merged is None:
                    continue
                if other_merged <= merged or other_merged - merged > SEVEN:
                    continue
                if is_revert(other.get("title"), other.get("body"), number) or is_followup(other, number):
                    failed = True
                    break
            if failed:
                failures += 1
        failure_rate = f"{failures}/{len(denominator)}"

    if ledger is None or not denominator:
        rework = "n/a"
        cost = "n/a"
    else:
        fix_counts = []
        cost_sums = []
        for pr in denominator:
            ref = pr.get("headRefName")
            issue = FACTORY_RE.match(ref).group(1)
            fix_counts.append(count_fixes(ledger, pr, issue))
            total, any_numeric = sum_cost(ledger, pr, issue)
            if any_numeric:
                cost_sums.append(total)
        rework = format_decimal(Decimal(sum(fix_counts)) / Decimal(len(fix_counts)), 1)
        if not cost_sums:
            cost = "n/a"
        else:
            mean = sum(cost_sums, Decimal(0)) / Decimal(len(cost_sums))
            cost = format_decimal(mean, 2)

    commits = flatten_pages(load_json(commits_path))
    ordered = []
    seen = set()
    for item in commits:
        if not isinstance(item, dict):
            raise SystemExit(7)
        sha = item.get("sha")
        if not isinstance(sha, str):
            raise SystemExit(7)
        if sha in seen:
            continue
        seen.add(sha)
        ordered.append((commit_when(item), sha, item))
    ordered.sort(key=lambda row: (row[0], row[1]))

    classified = []
    for _when, sha, _item in ordered:
        kind, stamp = classify(load_check_runs(sha), names)
        if kind == "neither":
            continue
        classified.append((kind, stamp))

    total_seconds = Decimal(0)
    completed = 0
    recovery_open = False
    for index, (kind, start) in enumerate(classified):
        if kind != "red" or start is None:
            continue
        end = None
        for later_kind, later_stamp in classified[index + 1 :]:
            if later_kind == "green" and later_stamp is not None:
                end = later_stamp
                break
        closed = end is not None and end < until_dt and end >= start
        if closed and since_dt <= start < until_dt:
            total_seconds += decimal_seconds(start, end)
            completed += 1
        still_open = end is None or end >= until_dt
        if still_open and start < until_dt:
            recovery_open = True

    if completed == 0:
        recovery = "n/a"
    else:
        recovery = format_decimal(total_seconds / Decimal(3600), 1)

    sys.stdout.write(
        "# Factory delivery metrics\n"
        f"repo: {repo}\n"
        f"since: {since}\n"
        f"until: {until}\n"
        "\n"
        "| metric | value |\n"
        "| --- | --- |\n"
        f"| change failure rate | {failure_rate} |\n"
        f"| rework rounds per pr | {rework} |\n"
        f"| recovery time hours | {recovery} |\n"
        f"| recovery open | {'yes' if recovery_open else 'no'} |\n"
        f"| cost per change usd | {cost} |\n"
    )


try:
    main()
except SystemExit:
    raise
except Exception:
    raise SystemExit(7)
PY
