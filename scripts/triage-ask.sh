#!/usr/bin/env bash
# Ask the owner before factory:ready.
#
# Usage: scripts/triage-ask.sh <owner/repo> <issue-number>
#
# Reads the issue title, body and comments. Issue text is untrusted data:
# it is parsed as text and never executed, and it is never copied into the
# question comment.
#
# Exit 0: ready is allowed. Prints nothing. Does not edit the issue, set a
# label, or write acceptance criteria. The owner already supplied one target
# repo from the closed set, one size (S, M or L), checkable done-checks, and
# a problem statement that is not a placeholder.
# Exit 2: withhold factory:ready. Prints a numbered comment for the caller
# to post, or prints nothing when that comment is already on the issue.
# Target repo and size are multiple choice. Any other missing fact is one
# short free-text question. This script does not add acceptance criteria.
# Exit 1: bad arguments, or the issue could not be read.
set -euo pipefail

die() { echo "triage-ask: $2" >&2; exit "$1"; }

repo=${1:-}
num=${2:-}
[[ $# -eq 2 ]] || die 1 "usage: scripts/triage-ask.sh <owner/repo> <issue-number>"
[[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die 1 "bad repo"
[[ $num =~ ^[1-9][0-9]*$ ]] || die 1 "bad issue number"

# Issue JSON stays in a file. A double-quoted shell variable would run
# command substitutions and backticks that appear in the issue text.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cat > "$work/decide.py" << 'PY'
import json
import re
import sys

# Closed sets. Target repo is one of these five. Size is S, M or L.
REPOS = (
    "adamsuk/software-factory",
    "adamsuk/gh-factory",
    "adamsuk/activity-feed",
    "adamsuk/line",
    "adamsuk/adamsuk",
)
SIZES = ("S", "M", "L")
MARKER = "<!-- factory:triage-ask -->"

REPO_ALT = "|".join(re.escape(name) for name in REPOS)
TARGET_RE = re.compile(rf"^[ \t]*Target repo:[ \t]*({REPO_ALT})[ \t]*$")
BARE_REPO_RE = re.compile(rf"^[ \t]*({REPO_ALT})[ \t]*$")
SIZE_RE = re.compile(r"^[ \t]*Size:[ \t]*([SML])[ \t]*$")
BARE_SIZE_RE = re.compile(r"^[ \t]*([SML])[ \t]*$")
TASK_RE = re.compile(r"^[ \t]*(?:[-*]|\d+\.)[ \t]+\[[ xX]\][ \t]*(.*)$")
HEADING_RE = re.compile(r"^[ \t]*#{1,6}[ \t]")
PLACEHOLDER_RE = re.compile(
    r"^(?:tbd|todo|n/?a|\?+|\.+|fix(?: it)?|wip|acceptance criteria|done-?checks?|tbc|xxx|it works)\.?$",
    re.I,
)
VAGUE_RE = re.compile(
    r"^(?:fix(?: the)? bug|improve(?: this)?|make it work|update(?: this)?|wip|todo|help|asap|\?+|tbd)\.?$",
    re.I,
)
CODE_RE = re.compile(r"`([^`\n]+)`")
WORD_RE = re.compile(r"\b(?:test|tests|diff|command)\b", re.I)
PATH_RE = re.compile(r"/|\b[\w.-]+\.(?:sh|py|ts|tsx|js|mjs|md|yml|yaml|json|go|rs)\b")


def norm(text):
    return text.replace("\r\n", "\n").replace("\r", "\n")


def comment_body(item):
    if isinstance(item, dict):
        body = item.get("body")
        return body if isinstance(body, str) else ""
    if isinstance(item, str):
        return item
    return ""


def unique(items):
    seen = []
    for item in items:
        if item not in seen:
            seen.append(item)
    return seen


def checkable(text):
    """A done-check names a test, a command, or a file to look at in the diff.

    Placeholder lines and vague lines are not checkable. The script never
    rewrites them.
    """
    collapsed = " ".join(text.split())
    if not collapsed or PLACEHOLDER_RE.match(collapsed):
        return False
    spans = CODE_RE.findall(collapsed)
    span_ok = False
    for span in spans:
        stripped = span.strip()
        if len(stripped) >= 3 and (
            WORD_RE.search(stripped) or PATH_RE.search(stripped) or " " in stripped
        ):
            span_ok = True
            break
    if span_ok and (WORD_RE.search(collapsed) or PATH_RE.search(collapsed)):
        return True
    if PATH_RE.search(collapsed) and WORD_RE.search(collapsed) and len(collapsed) >= 12:
        return True
    return False


def line_facts(line):
    repos = []
    sizes = []
    target = TARGET_RE.match(line)
    if target:
        repos.append(target.group(1))
    else:
        bare_repo = BARE_REPO_RE.match(line)
        if bare_repo:
            repos.append(bare_repo.group(1))
    size = SIZE_RE.match(line)
    if size:
        sizes.append(size.group(1))
    else:
        bare_size = BARE_SIZE_RE.match(line)
        if bare_size:
            sizes.append(bare_size.group(1))
    return repos, sizes


def ambiguous(prose):
    squashed = " ".join(prose.split())
    letters = re.sub(r"[^A-Za-z0-9]+", "", squashed)
    if len(letters) < 20:
        return True
    return VAGUE_RE.match(squashed) is not None


def questions_for(owner):
    repos = []
    sizes = []
    tasks = []
    prose = []
    for line in owner.split("\n"):
        if MARKER in line:
            continue
        task = TASK_RE.match(line)
        if task:
            tasks.append(task.group(1))
            continue
        line_repos, line_sizes = line_facts(line)
        repos.extend(line_repos)
        sizes.extend(line_sizes)
        if line_repos or line_sizes or HEADING_RE.match(line):
            continue
        prose.append(line)
    missing = []
    if len(unique(repos)) != 1:
        missing.append("repo")
    if len(unique(sizes)) != 1:
        missing.append("size")
    if not tasks:
        missing.append("ac-missing")
    elif not all(checkable(item) for item in tasks):
        missing.append("ac-vague")
    if ambiguous("\n".join(prose)):
        missing.append("problem")
    return missing


def render(missing):
    intro = (
        "Answer on this issue, in a comment or in the issue body. "
        "Your words stay on the issue. This comment does not add acceptance criteria. "
        "factory:ready stays off until those answers are on the issue."
    )
    lines = [MARKER, intro, ""]
    number = 1
    for key in missing:
        if key == "repo":
            lines.append(
                f"{number}. Which repository should this change land in? "
                "Pick one and reply with a line of the form `Target repo: <name>`."
            )
            for name in REPOS:
                lines.append(f"   - {name}")
        elif key == "size":
            lines.append(
                f"{number}. What size is this change? "
                "Pick one and reply with a line of the form `Size: <size>`."
            )
            for size in SIZES:
                lines.append(f"   - {size}")
        elif key == "ac-missing":
            lines.append(
                f"{number}. What are the done-checks? "
                "Reply with your own checklist. Each item should be verifiable "
                "by a test, a command, or a look at the diff."
            )
        elif key == "ac-vague":
            lines.append(
                f"{number}. Which done-checks are not verifiable yet? "
                "Reply with your own checklist. Each item should name a test, "
                "a command, or a file to look at in the diff."
            )
        elif key == "problem":
            lines.append(
                f"{number}. What should this change do? Reply in one or two sentences."
            )
        else:
            sys.stderr.write("triage-ask: unknown question\n")
            sys.exit(1)
        number += 1
    return "\n".join(lines) + "\n"


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.stderr.write("triage-ask: issue JSON could not be read\n")
        sys.exit(1)
    if not isinstance(data, dict):
        sys.stderr.write("triage-ask: issue JSON could not be read\n")
        sys.exit(1)
    # The title is not an answer. The owner writes the target repo, the size
    # and the done-checks in the body or a comment.
    body = data.get("body") if isinstance(data.get("body"), str) else ""
    raw_comments = data.get("comments")
    if not isinstance(raw_comments, list):
        raw_comments = []
    asked = False
    parts = [norm(body)]
    for item in raw_comments:
        text = norm(comment_body(item))
        if MARKER in text:
            asked = True
            continue
        parts.append(text)
    missing = questions_for("\n".join(parts))
    if not missing:
        sys.exit(0)
    if not asked:
        sys.stdout.write(render(missing))
    sys.exit(2)


if __name__ == "__main__":
    main()
PY
gh issue view "$num" --repo "$repo" --json title,body,comments > "$work/issue.json" \
  || die 1 "could not read issue"
rc=0
python3 "$work/decide.py" < "$work/issue.json" || rc=$?
exit "$rc"
