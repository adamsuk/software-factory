#!/usr/bin/env bash
# Behaviour tests for scripts/station-post.sh. ShellCheck covers this file.
# A fake gh records writes under $MOCK.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
post="$here/station-post.sh"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
MOCK=$root/mock
BIN=$root/bin
mkdir -p "$MOCK" "$BIN"

tname="startup"
fail() { echo "FAIL ($tname): $*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2] got [$1]"; }

cat > "$BIN/gh" << 'PY'
#!/usr/bin/env python3
import json, os, sys
root = os.environ["MOCK_GH"]
issue_path = os.path.join(root, "issue.json")
prs_path = os.path.join(root, "prs.json")
log_path = os.path.join(root, "log")

def load(path, default):
    if not os.path.exists(path):
        return default
    with open(path) as f:
        return json.load(f)

def save(path, data):
    with open(path, "w") as f:
        json.dump(data, f)

def record(args):
    with open(log_path, "a") as f:
        f.write(json.dumps(args) + "\n")

args = sys.argv[1:]
record(args)
if not args:
    sys.exit(2)
if args[0] == "issue" and args[1] == "view":
    sys.stdout.write(json.dumps(load(issue_path, {"labels": [], "comments": []})))
    sys.exit(0)
if args[0] == "issue" and args[1] == "comment":
    issue = load(issue_path, {"labels": [], "comments": []})
    body = args[args.index("--body") + 1]
    issue.setdefault("comments", []).append({"body": body})
    save(issue_path, issue)
    sys.exit(0)
if args[0] == "issue" and args[1] == "edit":
    issue = load(issue_path, {"labels": [], "comments": []})
    names = [x["name"] for x in issue.get("labels", [])]
    i = 0
    while i < len(args):
        if args[i] == "--remove-label" and i + 1 < len(args):
            names = [n for n in names if n != args[i + 1]]
            i += 2
            continue
        if args[i] == "--add-label" and i + 1 < len(args):
            if args[i + 1] not in names:
                names.append(args[i + 1])
            i += 2
            continue
        i += 1
    issue["labels"] = [{"name": n} for n in names]
    save(issue_path, issue)
    sys.exit(0)
if args[0] == "pr" and args[1] == "list":
    sys.stdout.write(json.dumps(load(prs_path, [])))
    sys.exit(0)
if args[0] == "pr" and args[1] == "view":
    number = args[2]
    for pr in load(prs_path, []):
        if str(pr["number"]) == number:
            sys.stdout.write(json.dumps({"comments": pr.get("comments", [])}))
            sys.exit(0)
    sys.stderr.write("not found\n")
    sys.exit(1)
if args[0] == "pr" and args[1] == "create":
    prs = load(prs_path, [])
    def opt(flag):
        return args[args.index(flag) + 1]
    number = len(prs) + 1
    prs.append({
        "number": number,
        "headRefName": opt("--head"),
        "title": opt("--title"),
        "body": opt("--body"),
        "comments": [],
    })
    save(prs_path, prs)
    sys.exit(0)
if args[0] == "pr" and args[1] == "comment":
    number = args[2]
    body = args[args.index("--body") + 1]
    prs = load(prs_path, [])
    for pr in prs:
        if str(pr["number"]) == number:
            pr.setdefault("comments", []).append({"body": body})
    save(prs_path, prs)
    sys.exit(0)
if args[0] == "pr" and args[1] == "merge":
    sys.stderr.write("merge was called\n")
    sys.exit(9)
sys.stderr.write("unmocked gh: %s\n" % " ".join(args))
sys.exit(2)
PY
chmod +x "$BIN/gh" "$post"

export MOCK_GH=$MOCK
export PATH="$BIN:$PATH"

reset_issue() {
  local label=$1
  printf '%s\n' "{\"labels\":[{\"name\":\"${label}\"}],\"comments\":[]}" > "$MOCK/issue.json"
  printf '%s\n' '[]' > "$MOCK/prs.json"
  : > "$MOCK/log"
}

label_names() {
  jq -r '.labels[].name' "$MOCK/issue.json" | paste -sd, -
}

comment_count() {
  jq '.comments | length' "$MOCK/issue.json"
}

tname="triage ready"
reset_issue "factory:triage"
printf '%s\n' "Goal" "Target repo: acme/widgets" > "$root/triage.md"
out=$("$post" triage --repo acme/widgets --issue 7 --status ready --body-file "$root/triage.md")
assert_eq "$(label_names)" "factory:ready"
assert_eq "$(comment_count)" "1"
first=$(jq -r '.comments[0].body' "$MOCK/issue.json" | head -n 1)
assert_eq "$first" "<!-- factory:triage -->"
printf '%s\n' "$out" | grep -q 'factory:ready' || fail "missing ready note"

tname="second triage refused"
set +e
"$post" triage --repo acme/widgets --issue 7 --status ready --body-file "$root/triage.md" >"$root/err" 2>&1
rc=$?
set -e
assert_eq "$rc" "4"
assert_eq "$(comment_count)" "1"

tname="pickup"
reset_issue "factory:ready"
out=$("$post" pickup --repo acme/widgets --issue 7 --branch factory/7-widgets)
assert_eq "$(label_names)" "factory:building"
first=$(jq -r '.comments[0].body' "$MOCK/issue.json" | head -n 1)
assert_eq "$first" "<!-- factory:building -->"
printf '%s\n' "$out" | grep -q 'factory:building' || fail "missing building note"

tname="pickup twice"
out=$("$post" pickup --repo acme/widgets --issue 7 --branch factory/7-widgets)
assert_eq "$(comment_count)" "1"
printf '%s\n' "$out" | grep -q 'already posted' || fail "second pickup wrote again"

tname="pickup without ready"
reset_issue "factory:triage"
set +e
"$post" pickup --repo acme/widgets --issue 7 --branch factory/7-widgets >"$root/err" 2>&1
rc=$?
set -e
assert_eq "$rc" "4"

tname="bad branch"
reset_issue "factory:building"
printf '%s\n' "Closes #7" > "$root/body.md"
set +e
"$post" pr --repo acme/widgets --issue 7 --head temp-branch --title "feat: x (#7)" --body-file "$root/body.md" >"$root/err" 2>&1
rc=$?
set -e
assert_eq "$rc" "2"
grep -q '"pr","create"' "$MOCK/log" && fail "created a pr for a bad branch"
assert_eq "$(jq 'length' "$MOCK/prs.json")" "0"

tname="open pr"
out=$("$post" pr --repo acme/widgets --issue 7 --head factory/7-widgets --title "feat: x (#7)" --body-file "$root/body.md")
assert_eq "$(label_names)" "factory:gate"
assert_eq "$(jq 'length' "$MOCK/prs.json")" "1"
assert_eq "$(jq -r '.[0].headRefName' "$MOCK/prs.json")" "factory/7-widgets"
printf '%s\n' "$out" | grep -q 'acme/widgets#1' || fail "did not name the pr"
grep -q '"merge"' "$MOCK/log" && fail "merged"

tname="second pr refused"
printf '%s\n' "Closes #7" > "$root/body2.md"
set +e
"$post" pr --repo acme/widgets --issue 7 --head factory/7-other --title "feat: y (#7)" --body-file "$root/body2.md" >"$root/err" 2>&1
rc=$?
set -e
assert_eq "$rc" "4"
assert_eq "$(jq 'length' "$MOCK/prs.json")" "1"

tname="same branch reused"
out=$("$post" pr --repo acme/widgets --issue 7 --head factory/7-widgets --title "feat: x (#7)" --body-file "$root/body.md")
assert_eq "$(jq 'length' "$MOCK/prs.json")" "1"
printf '%s\n' "$out" | grep -q 'already open' || fail "did not reuse the pr"

tname="verdict pass does not merge"
out=$("$post" verdict --repo acme/widgets --pr 1 --issue 7 --sha abcdef1234567890 \
  --verdict PASS --protected no --summary "Meets the acceptance criteria.")
assert_eq "$(label_names)" "factory:merge"
grep -q '"merge"' "$MOCK/log" && fail "merged on PASS"
jq -e --arg m '<!-- factory:independent-review v2 sha=abcdef1234567890 -->' \
  '.[0].comments | any(.[]; .body | startswith($m))' \
  "$MOCK/prs.json" >/dev/null || fail "missing independent review comment"
printf '%s\n' "$out" | grep -q 'not merged' || fail "did not say it was not merged"

tname="verdict escalate blocks"
reset_issue "factory:review"
printf '%s\n' '[]' > "$MOCK/prs.json"
# seed the open pr the verdict comments on
python3 - << PY
import json
p = "$MOCK/prs.json"
json.dump([{"number": 1, "headRefName": "factory/7-widgets", "body": "Closes #7", "comments": []}], open(p, "w"))
PY
out=$("$post" verdict --repo acme/widgets --pr 1 --issue 7 --sha abcdef1234567890 \
  --verdict ESCALATE --protected no --summary "Protected path.")
assert_eq "$(label_names)" "factory:blocked"
first=$(jq -r '.comments[-1].body' "$MOCK/issue.json" | head -n 1)
assert_eq "$first" "<!-- factory:review -->"
grep -q 'Scott must act' "$MOCK/issue.json" || fail "missing scott line"

tname="closes on a non-factory branch"
reset_issue "factory:building"
python3 - << PY
import json
json.dump([{"number": 9, "headRefName": "temp-branch", "body": "Closes #7", "comments": []}], open("$MOCK/prs.json", "w"))
PY
set +e
"$post" pr --repo acme/widgets --issue 7 --head factory/7-widgets --title "feat: x (#7)" --body-file "$root/body.md" >"$root/err" 2>&1
rc=$?
set -e
assert_eq "$rc" "4"
assert_eq "$(jq 'length' "$MOCK/prs.json")" "1"

tname="pickup repairs a missed label"
reset_issue "factory:ready"
python3 - << 'PY'
import json, os
p = os.environ["MOCK_GH"] + "/issue.json"
issue = {"labels": [{"name": "factory:ready"}], "comments": [{"body": "<!-- factory:building -->\nPicked up.\n"}]}
json.dump(issue, open(p, "w"))
PY
out=$("$post" pickup --repo acme/widgets --issue 7 --branch factory/7-widgets)
assert_eq "$(label_names)" "factory:building"
assert_eq "$(comment_count)" "1"
printf '%s\n' "$out" | grep -q 'already posted' || fail "pickup retry posted a second comment"

tname="dry-run writes nothing"
reset_issue "factory:triage"
: > "$MOCK/log"
out=$("$post" --dry-run triage --repo acme/widgets --issue 7 --status ready --body-file "$root/triage.md")
assert_eq "$(label_names)" "factory:triage"
assert_eq "$(comment_count)" "0"
printf '%s\n' "$out" | grep -q 'factory:triage' || fail "dry-run hid the comment"
grep -q '"issue", "comment"' "$MOCK/log" && fail "dry-run commented"

echo "ok"
