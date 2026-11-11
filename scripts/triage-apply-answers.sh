#!/usr/bin/env bash
# Write the approver's triage answers back into the issue body.
#
# Usage: scripts/triage-apply-answers.sh <owner/repo> <issue-number>
#
# Reads the issue body and comments. Issue text is untrusted data: it is
# parsed as text and never executed. Only the numbered answers to the
# target-repo and size questions of scripts/triage-ask.sh are read, and only
# from the approver (FACTORY_APPROVER_LOGIN, else the repo owner, the same
# rule as scripts/ready-gate.sh). Comments from anyone else, the factory app
# included, are ignored.
#
# An answer is a line in an approver comment that is, after an optional
# `N.` or `N)` number, one of: `Target repo: <name>`, a bare <name> from the
# closed set, `Size: <S|M|L>` or a bare S, M or L. The closed set is
# FACTORY_REPOS (space-separated owner/repo), five-repo default when unset.
# The latest answer wins. Anything else in a comment is ignored.
#
# The only lines this script writes are `Target repo:` and `Size:` in the
# issue body, plus the `<!-- factory:triage-ask applied -->` marker. Other
# lines are copied through unchanged. The edit is `gh issue edit --body-file`.
#
# Exit 0: the body was changed (answers applied).
# Exit 2: nothing to apply (no approver answer, or the body already says it).
# Exit 1: bad arguments, or the issue could not be read or written.
set -euo pipefail

die() { echo "triage-apply-answers: $2" >&2; exit "$1"; }

repo=${1:-}
num=${2:-}
[[ $# -eq 2 ]] || die 1 "usage: scripts/triage-apply-answers.sh <owner/repo> <issue-number>"
[[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die 1 "bad repo"
[[ $num =~ ^[1-9][0-9]*$ ]] || die 1 "bad issue number"

approver=${FACTORY_APPROVER_LOGIN:-${repo%%/*}}
approver=$(printf '%s' "$approver" | tr -d '[:space:]')
[[ -n $approver ]] || approver=${repo%%/*}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cat > "$work/apply.py" << 'PY'
import json
import os
import re
import sys

DEFAULT_REPOS = (
    "adamsuk/software-factory",
    "adamsuk/gh-factory",
    "adamsuk/activity-feed",
    "adamsuk/line",
    "adamsuk/adamsuk",
)
REPO_TOKEN = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
APPLIED = "<!-- factory:triage-ask applied -->"
NUM = r"(?:\d+[.)][ \t]+)?"
TARGET_RE = re.compile(r"^[ \t]*" + NUM + r"Target repo:[ \t]*(\S+)[ \t]*$", re.I)
BARE_REPO_RE = re.compile(r"^[ \t]*" + NUM + r"(\S+)[ \t]*$")
SIZE_RE = re.compile(r"^[ \t]*" + NUM + r"Size:[ \t]*([SML])[ \t]*\.?[ \t]*$")
BARE_SIZE_RE = re.compile(r"^[ \t]*" + NUM + r"([SML])[ \t]*\.?[ \t]*$")
BODY_TARGET_RE = re.compile(r"^[ \t]*Target repo:", re.I)
BODY_SIZE_RE = re.compile(r"^[ \t]*Size:")


def repos():
    found = []
    for token in (os.environ.get("FACTORY_REPOS") or "").split():
        if REPO_TOKEN.fullmatch(token) and token not in found:
            found.append(token)
    return tuple(found) or DEFAULT_REPOS


BY_LOWER = {name.lower(): name for name in repos()}


def known_repo(token):
    token = re.sub(r"^[^a-z0-9]+|[^a-z0-9]+$", "", token.lower())
    return BY_LOWER.get(token)


def answers_in(text):
    repo = size = None
    for line in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        m = TARGET_RE.match(line) or BARE_REPO_RE.match(line)
        if m and known_repo(m.group(1)):
            repo = known_repo(m.group(1))
            continue
        m = SIZE_RE.match(line) or BARE_SIZE_RE.match(line)
        if m:
            size = m.group(1)
    return repo, size


def set_line(lines, pattern, new):
    # Replace every matching line with the one answer. Add it when absent.
    out = []
    hit = False
    for line in lines:
        if pattern.match(line):
            eol = "\r\n" if line.endswith("\r\n") else "\n"
            out.append(new + eol)
            hit = True
        else:
            out.append(line)
    if not hit:
        if out and not out[-1].endswith("\n"):
            out[-1] += "\n"
        if out and out[-1].strip():
            out.append("\n")
        out.append(new + "\n")
    return out


def main():
    approver = sys.argv[1]
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.stderr.write("triage-apply-answers: issue JSON could not be read\n")
        sys.exit(1)
    if not isinstance(data, dict):
        sys.stderr.write("triage-apply-answers: issue JSON could not be read\n")
        sys.exit(1)
    body = data.get("body") if isinstance(data.get("body"), str) else ""
    comments = data.get("comments") if isinstance(data.get("comments"), list) else []
    repo = size = None
    for item in comments:
        if not isinstance(item, dict):
            continue
        author = item.get("author")
        login = author.get("login") if isinstance(author, dict) else None
        text = item.get("body")
        if login != approver or not isinstance(text, str):
            continue
        # The question comment carries the marker and is not an answer.
        if "<!-- factory:triage-ask -->" in text:
            continue
        r, s = answers_in(text)
        repo = r or repo
        size = s or size
    if not repo and not size:
        sys.exit(2)
    lines = body.splitlines(keepends=True)
    if repo:
        lines = set_line(lines, BODY_TARGET_RE, f"Target repo: {repo}")
    if size:
        lines = set_line(lines, BODY_SIZE_RE, f"Size: {size}")
    new = "".join(lines)
    if new == body:
        sys.exit(2)
    if APPLIED not in new:
        if not new.endswith("\n"):
            new += "\n"
        new += "\n" + APPLIED + "\n"
    sys.stdout.write(new)


if __name__ == "__main__":
    main()
PY
gh issue view "$num" --repo "$repo" --json body,comments > "$work/issue.json" \
  || die 1 "could not read issue"
rc=0
python3 "$work/apply.py" "$approver" < "$work/issue.json" > "$work/body.md" || rc=$?
[[ $rc -eq 0 ]] || exit "$rc"
gh issue edit "$num" --repo "$repo" --body-file "$work/body.md" > /dev/null \
  || die 1 "could not write issue body"
echo "triage-apply-answers: applied approver answers to #${num}" >&2
exit 0
