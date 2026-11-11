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
#
# The closed set is FACTORY_REPOS (space-separated owner/repo). Unset or
# empty keeps the five-repo default. An answer counts only when author.login
# is FACTORY_APPROVER_LOGIN, which defaults to the owner of the first repo
# in that set. The already-asked marker also counts from that approver and
# from the factory app: software-factory-line, with or without a trailing
# [bot], and FACTORY_LOGIN the same way when it is set. An app comment is
# never an answer. The issue body is the filer's text and is still read.
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
import os
import re
import sys

# Closed sets. Target repo is one entry of FACTORY_REPOS. Unset or empty
# keeps the five-repo default so an operator who has not set the variable
# still matches the historical list. Size is S, M or L, with an optional
# trailing full stop (the factory writes "Size: M.").
DEFAULT_REPOS = (
    "adamsuk/software-factory",
    "adamsuk/gh-factory",
    "adamsuk/activity-feed",
    "adamsuk/line",
    "adamsuk/adamsuk",
)
REPO_TOKEN = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
SIZES = ("S", "M", "L")
MARKER = "<!-- factory:triage-ask -->"
# Documented app slug. gh issue comment from the app shows this login, with
# or without a trailing [bot]. FACTORY_LOGIN, when set, is accepted as well.
DEFAULT_APP_LOGIN = "software-factory-line"
BOT_SUFFIX = "[bot]"


def load_repos():
    raw = os.environ.get("FACTORY_REPOS") or ""
    found = []
    for token in raw.split():
        if REPO_TOKEN.fullmatch(token) and token not in found:
            found.append(token)
    if not found:
        return DEFAULT_REPOS
    return tuple(found)


def approver_login(repos):
    raw = os.environ.get("FACTORY_APPROVER_LOGIN") or ""
    if isinstance(raw, str):
        raw = raw.strip()
    else:
        raw = ""
    if raw:
        return raw
    if repos:
        owner = repos[0].split("/", 1)[0]
        if owner:
            return owner
    return "adamsuk"


REPOS = load_repos()
APPROVER = approver_login(REPOS)
REPO_ALT = "|".join(re.escape(name) for name in REPOS)
# The watcher's target_repo_lines lowercases the line, takes the first token
# after "target repo:" and strips punctuation from its ends. Same rule here,
# so an answer the build accepts is an answer this script accepts.
REPO_BY_LOWER = {name.lower(): name for name in REPOS}
TARGET_RE = re.compile(r"^[ \t]*Target repo:[ \t]*(\S+)", re.I)
BARE_REPO_RE = re.compile(rf"^[ \t]*({REPO_ALT})[ \t]*$", re.I)
SIZE_RE = re.compile(r"^[ \t]*Size:[ \t]*([SML])[ \t]*(?:\.[ \t]*)?$")
BARE_SIZE_RE = re.compile(r"^[ \t]*([SML])[ \t]*(?:\.[ \t]*)?$")
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
OBSERVABLE_RE = re.compile(
    r"\b(?:pass(?:es|ed)?|fail(?:s|ed)?|returns?|exits?|contains?|documents?|"
    r"prints?|shows?|includes?|matches|records?|lists?|equals?|remains?)\b",
    re.I,
)


def norm(text):
    return text.replace("\r\n", "\n").replace("\r", "\n")


def comment_body(item):
    if isinstance(item, dict):
        body = item.get("body")
        return body if isinstance(body, str) else ""
    if isinstance(item, str):
        return item
    return ""


def comment_author(item):
    if not isinstance(item, dict):
        return ""
    author = item.get("author")
    if not isinstance(author, dict):
        return ""
    login = author.get("login")
    return login if isinstance(login, str) else ""


def login_forms(login):
    # The raw login, plus the same value with a trailing [bot] removed or added.
    if not isinstance(login, str):
        return set()
    raw = login.strip()
    if not raw:
        return set()
    forms = {raw}
    if raw.endswith(BOT_SUFFIX):
        bare = raw[: -len(BOT_SUFFIX)].strip()
        if bare:
            forms.add(bare)
    else:
        forms.add(raw + BOT_SUFFIX)
    return forms


def app_logins():
    # The documented slug always counts, so a preset FACTORY_LOGIN cannot hide
    # the comment the app posts. A set FACTORY_LOGIN counts too, marker only.
    forms = login_forms(DEFAULT_APP_LOGIN)
    forms |= login_forms(os.environ.get("FACTORY_LOGIN") or "")
    return forms


APP_LOGINS = app_logins()


def approver_comment(item):
    # Answers, and the asked marker. gh issue view --json comments includes
    # author.login. Anyone else is not an answer.
    return comment_author(item) == APPROVER


def app_comment(item):
    # Factory app login. The asked marker counts. The body is never an answer.
    return comment_author(item) in APP_LOGINS


def unique(items):
    seen = []
    for item in items:
        if item not in seen:
            seen.append(item)
    return seen


def checkable(text):
    """A done-check names a test, a command, a file, or a concrete outcome.

    Placeholder lines and vague lines are not checkable. The script never
    rewrites them. A backtick span still has to name something verifiable.
    Plain prose passes when it names a path, a test or command, or a
    concrete observable result of reasonable length.
    """
    collapsed = " ".join(text.split())
    if not collapsed or PLACEHOLDER_RE.match(collapsed) or VAGUE_RE.match(collapsed):
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
    has_path = PATH_RE.search(collapsed) is not None
    has_word = WORD_RE.search(collapsed) is not None
    has_outcome = OBSERVABLE_RE.search(collapsed) is not None
    if span_ok and (has_word or has_path or has_outcome):
        return True
    if len(collapsed) >= 12 and (has_path or has_word):
        return True
    words = collapsed.split()
    if len(collapsed) >= 24 and len(words) >= 5 and has_outcome:
        return True
    return False


def known_repo(token):
    # The FACTORY_REPOS spelling of a repo token, or None outside the set.
    token = re.sub(r"^[^a-z0-9]+|[^a-z0-9]+$", "", token.lower())
    return REPO_BY_LOWER.get(token)


def line_facts(line):
    repos = []
    sizes = []
    target = TARGET_RE.match(line)
    bare_repo = None if target else BARE_REPO_RE.match(line)
    found = target or bare_repo
    name = known_repo(found.group(1)) if found else None
    if name:
        repos.append(name)
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


def latest_answer(answers, index):
    # The last Target repo (index 0) or Size (index 1) the approver wrote in
    # a comment, or None. Comments are in posting order.
    found = None
    for text in answers:
        for line in text.split("\n"):
            if MARKER in line or TASK_RE.match(line):
                continue
            values = line_facts(line)[index]
            if values:
                found = values[-1]
    return found


def questions_for(owner, answers=()):
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
    # The approver's latest comment value settles target repo and size. It
    # wins over the body and over the approver's earlier comments. Without
    # one, two different values stay ambiguous.
    repo_answer = latest_answer(answers, 0)
    if repo_answer:
        repos = [repo_answer]
    size_answer = latest_answer(answers, 1)
    if size_answer:
        sizes = [size_answer]
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
    answers = []
    for item in raw_comments:
        text = norm(comment_body(item))
        if approver_comment(item):
            if MARKER in text:
                asked = True
                continue
            parts.append(text)
            answers.append(text)
            continue
        # The app may post the marker. Skip the body either way so a bot
        # comment cannot supply Target repo, Size, done-checks, or the problem.
        if app_comment(item):
            if MARKER in text:
                asked = True
            continue
    missing = questions_for("\n".join(parts), answers)
    if not missing:
        sys.exit(0)
    if not asked:
        sys.stdout.write(render(missing))
    sys.exit(2)


if __name__ == "__main__":
    main()
PY
# Apply the approver's numbered answers to the body first (#347), so the
# ready check below reads them. Opt-in with FACTORY_TRIAGE_APPLY=1: it edits
# the issue body, which a read-only caller must not do. Exit 2 means there was
# nothing to apply.
if [[ ${FACTORY_TRIAGE_APPLY:-0} == 1 ]]; then
  apply_rc=0
  bash "$(dirname "${BASH_SOURCE[0]}")/triage-apply-answers.sh" "$repo" "$num" >&2 || apply_rc=$?
  [[ $apply_rc -eq 0 || $apply_rc -eq 2 ]] || die 1 "could not apply answers"
fi
gh issue view "$num" --repo "$repo" --json title,body,comments > "$work/issue.json" \
  || die 1 "could not read issue"
rc=0
python3 "$work/decide.py" < "$work/issue.json" || rc=$?
exit "$rc"
