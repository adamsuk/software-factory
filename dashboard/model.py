"""Pure functions from raw GitHub snapshots to the dashboard view model.

Issue and PR text is untrusted (AGENTS.md section 1): it is only matched
against fixed markers here, never interpreted, and render.py escapes it.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime, timezone

# AGENTS.md section 9, in pipeline order.
STATUSES = ["triage", "ready", "building", "gate", "review", "merge", "release", "done", "blocked"]
STALE_DAYS = 3
STALE_STATUSES = {"building", "gate", "review"}
DEPENDABOT = {"app/dependabot", "dependabot", "dependabot[bot]"}
BOT_LOGINS = {"software-factory-line", "software-factory-line[bot]", "app/software-factory-line"}

# Mirrors scripts/protected-paths.sh.
PROTECTED_RE = re.compile(
    r"^(\.github/(workflows|actions)/|\.github/factory\.yml$|\.github/CODEOWNERS$|\.coderabbit\.yaml$"
    r"|CODEOWNERS$|AGENTS\.md$|agents/)|(^|/)(package-lock\.json|pnpm-lock\.yaml|yarn\.lock|go\.sum|[^/]*\.lock)$"
)
WORK_ORDER_RE = re.compile(r"^agents/work-orders/")

IR_MARKER_RE = re.compile(r"^<!-- factory:independent-review v2 sha=([0-9a-fA-F]{7,40}) -->$")
# Both forms are in use: "(after CodeRabbit)" from the watcher, without it from older station posts.
IR_VERDICT_RE = re.compile(r"^\*\*Independent review(?: \(after CodeRabbit\))?: (PASS|FIX|ESCALATE)\*\* on ")
APPROVE_MARKER = "<!-- factory:approve -->"


def parse_time(s: str | None) -> datetime | None:
    if not s:
        return None
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def nodes(obj: dict | None, key: str) -> list:
    return ((obj or {}).get(key) or {}).get("nodes") or []


def lines(body: str | None) -> list[str]:
    return [ln.rstrip("\r") for ln in (body or "").split("\n")]


def is_protected(path: str) -> bool:
    return bool(PROTECTED_RE.search(path)) and not WORK_ORDER_RE.match(path)


def required_checks(factory_yml: str | None) -> list[str] | None:
    """Top-level required_checks list, or None when absent or unreadable."""
    if not factory_yml:
        return None
    try:
        import yaml  # optional; same source as gate-issue.sh
        data = yaml.safe_load(factory_yml)
        val = data.get("required_checks") if isinstance(data, dict) else None
        return [str(v) for v in val] if isinstance(val, list) else None
    except ImportError:
        pass
    except Exception:
        return None
    out, inside = [], False
    for ln in factory_yml.splitlines():
        if re.match(r"^required_checks:\s*(#.*)?$", ln):
            inside = True
            continue
        if inside:
            m = re.match(r"^\s+-\s+(.+?)\s*(#.*)?$", ln)
            if m:
                out.append(m.group(1).strip("'\""))
            elif ln.strip() and not ln.lstrip().startswith("#"):
                break
    return out if inside else None


@dataclass
class Check:
    name: str
    state: str  # green | pending | failing
    url: str = ""


@dataclass
class PR:
    repo: str
    number: int
    title: str
    url: str
    author: str
    draft: bool
    head: str
    merge_state: str
    checks: str  # green | pending | failing | none
    failing: list[str]
    verdict: str  # as scripts/pr-status.sh
    ir_verdict: str  # PASS | FIX | ESCALATE | none (independent review on the head, trusted authors)
    protected_files: list[str]
    issues: list[tuple[str, int]]
    labels: list[str]
    threads: int
    updated: datetime | None

    @property
    def protected(self) -> bool:
        return bool(self.protected_files)

    @property
    def key(self) -> str:
        return f"{self.repo}#{self.number}"


@dataclass
class Issue:
    repo: str
    number: int
    title: str
    url: str
    labels: list[str]
    statuses: list[str]
    since: datetime | None
    priority: int  # 0..3, 4 unprioritised
    flagged: bool
    reason_url: str  # the latest factory marker comment saying why it is blocked, or ""
    approved: bool  # a <!-- factory:approve --> comment from the approver exists
    protected_hold: bool  # the factory's blocked comment says the build touched protected paths
    prs: list[PR] = field(default_factory=list)

    @property
    def status(self) -> str | None:
        return self.statuses[0] if len(self.statuses) == 1 else None

    @property
    def key(self) -> str:
        return f"{self.repo}#{self.number}"


@dataclass
class Action:
    group: str  # unblock | review | triage
    title: str
    why: str
    key: str
    url: str
    links: list[tuple[str, str]]
    copy: str = ""
    subject: str = ""


@dataclass
class View:
    now: datetime
    repos: list[str]
    errors: list[tuple[str, str]]
    issues: list[Issue]
    prs: list[PR]
    actions: list[Action]
    running: list[Issue]
    pending_prs: list[PR]
    board: dict[str, list[Issue]]
    unlabelled: list[Issue]
    multi: list[Issue]
    stale: list[Issue]
    local: list[dict] = field(default_factory=list)


def classify_checks(contexts: list[dict], required: list[str] | None) -> tuple[str, list[Check]]:
    """Same rules as scripts/pr-status.sh: required list when declared, else every check."""
    seen: dict[str, Check] = {}
    for c in contexts:
        if c.get("__typename") == "StatusContext":
            name, url = c.get("context") or "", c.get("targetUrl") or ""
            st = {"SUCCESS": "green", "PENDING": "pending", "EXPECTED": "pending"}.get(c.get("state") or "", "failing")
        else:
            name, url = c.get("name") or "", c.get("detailsUrl") or ""
            if (c.get("status") or "") != "COMPLETED":
                st = "pending"
            else:
                st = "green" if (c.get("conclusion") or "") in ("SUCCESS", "NEUTRAL", "SKIPPED") else "failing"
        seen[name] = Check(name, st, url)
    if required:
        judged = [seen.get(n) or Check(n, "pending") for n in required]
    else:
        judged = list(seen.values())
    if not judged:
        return "none", []
    if any(c.state == "pending" for c in judged):
        return "pending", judged
    if any(c.state == "failing" for c in judged):
        return "failing", judged
    return "green", judged


def ir_verdict(comments: list[dict], head: str, approver: str) -> str:
    trusted = BOT_LOGINS | {approver}
    verdict = "none"
    for c in comments:
        ls = lines(c.get("body"))
        m = IR_MARKER_RE.match(ls[0]) if ls else None
        if not m or not head.lower().startswith(m.group(1).lower()):
            continue
        if ((c.get("author") or {}).get("login") or "") not in trusted:
            continue
        v = IR_VERDICT_RE.match(ls[1]) if len(ls) > 1 else None
        verdict = v.group(1) if v else "unreadable"
    return verdict


def pr_verdict(checks: str, threads: int, reviews: list[dict], head: str) -> str:
    on_head = {}
    for r in sorted(reviews, key=lambda r: r.get("submittedAt") or ""):
        if ((r.get("commit") or {}).get("oid") or "") == head:
            on_head[(r.get("author") or {}).get("login") or ""] = r.get("state")
    if checks == "failing":
        return "failing-ci"
    if threads:
        return "open-threads"
    if "CHANGES_REQUESTED" in on_head.values():
        return "changes-requested"
    if checks in ("pending", "none"):
        return "pending"
    if "APPROVED" not in on_head.values():
        return "needs-review"
    return "ready"


def build_pr(repo: str, raw: dict, required: list[str] | None, approver: str) -> PR:
    head = raw.get("headRefOid") or ""
    commits = nodes(raw, "commits")
    rollup = ((commits[0].get("commit") or {}).get("statusCheckRollup") or {}) if commits else {}
    checks, judged = classify_checks(nodes(rollup, "contexts"), required)
    threads = sum(1 for t in nodes(raw, "reviewThreads") if not t.get("isResolved"))
    return PR(
        repo=repo,
        number=raw["number"],
        title=raw.get("title") or "",
        url=raw.get("url") or "",
        author=(raw.get("author") or {}).get("login") or "",
        draft=bool(raw.get("isDraft")),
        head=head,
        merge_state=raw.get("mergeStateStatus") or "",
        checks=checks,
        failing=[c.name for c in judged if c.state == "failing"],
        verdict=pr_verdict(checks, threads, nodes(raw, "latestReviews"), head),
        ir_verdict=ir_verdict(nodes(raw, "comments"), head, approver),
        protected_files=[f["path"] for f in nodes(raw, "files") if is_protected(f.get("path") or "")],
        issues=[((i.get("repository") or {}).get("nameWithOwner") or repo, i["number"])
                for i in nodes(raw, "closingIssuesReferences")],
        labels=[lb["name"] for lb in nodes(raw, "labels")],
        threads=threads,
        updated=parse_time(raw.get("updatedAt")),
    )


def priority_rank(labels: list[str]) -> int:
    for i in range(4):
        if f"priority: P{i}" in labels:
            return i
    return 4


def build_issue(repo: str, raw: dict, approver: str) -> Issue:
    labels = [lb["name"] for lb in nodes(raw, "labels")]
    statuses = [lb.split(":", 1)[1] for lb in labels if lb.startswith("factory:") and lb.split(":", 1)[1] in STATUSES]
    statuses.sort(key=STATUSES.index)
    since = None
    if len(statuses) == 1:
        for ev in nodes(raw, "timelineItems"):
            if ((ev.get("label") or {}).get("name")) == f"factory:{statuses[0]}":
                since = parse_time(ev.get("createdAt"))
    trusted = BOT_LOGINS | {approver}
    reason, approved, protected_hold = "", False, False
    for c in nodes(raw, "comments"):
        who = (c.get("author") or {}).get("login") or ""
        ls = lines(c.get("body"))
        if who in trusted and ls and (ls[0] == "<!-- factory:blocked -->" or (
                ls[0] == "<!-- factory:review -->" and len(ls) > 1 and ls[1].startswith("blocked:"))):
            reason = c.get("url") or ""
            protected_hold = "protected path" in (c.get("body") or "").lower()
        if who == approver and APPROVE_MARKER in (c.get("body") or ""):
            approved = True
    if not reason and "factory:blocked" in labels:
        cs = nodes(raw, "comments")
        reason = (cs[-1].get("url") or "") if cs else ""
    return Issue(
        repo=repo,
        number=raw["number"],
        title=raw.get("title") or "",
        url=raw.get("url") or "",
        labels=labels,
        statuses=statuses,
        since=since or parse_time(raw.get("createdAt")) if len(statuses) == 1 else None,
        priority=priority_rank(labels),
        flagged="priority: next" in labels,
        reason_url=reason,
        approved=approved,
        protected_hold=protected_hold,
    )


def pr_links(pr: PR) -> list[tuple[str, str]]:
    return [("PR", pr.url), ("Files", pr.url + "/files"), ("Checks", pr.url + "/checks")]


def actions_for(issues: list[Issue], prs: list[PR]) -> list[Action]:
    out: list[Action] = []
    by_key = {i.key: i for i in issues}
    acted: set[str] = set()

    for pr in prs:
        linked = [by_key[f"{r}#{n}"] for r, n in pr.issues if f"{r}#{n}" in by_key]
        blocked_issue = any(i.status == "blocked" for i in linked)
        if pr.ir_verdict == "ESCALATE":
            out.append(Action("unblock", "Escalated by the independent review", "ESCALATE on the current head",
                              pr.key, pr.url, pr_links(pr)))
        elif pr.checks == "failing" and (pr.draft or blocked_issue):
            out.append(Action("unblock", "Blocked by failing CI", "failing: " + ", ".join(pr.failing),
                              pr.key, pr.url, pr_links(pr)))
        elif pr.checks == "failing" and pr.author in DEPENDABOT:
            out.append(Action("unblock", "Dependabot PR failing CI", "no automatic fix for Dependabot (section 10.3); "
                              "failing: " + ", ".join(pr.failing), pr.key, pr.url, pr_links(pr)))
        elif pr.ir_verdict == "PASS" and pr.checks == "green" and pr.threads == 0:
            why = "PASS + green, protected paths: " + ", ".join(pr.protected_files[:3]) if pr.protected \
                else "PASS + green on the current head"
            out.append(Action("review", "Ready for your approval", why, pr.key, pr.url, pr_links(pr)))
        elif "needs-scott" in pr.labels:
            out.append(Action("unblock", "Needs you", "labelled needs-scott", pr.key, pr.url, pr_links(pr)))
        else:
            continue
        out[-1].subject = pr.title
        acted.add(pr.key)
        acted.update(i.key for i in linked)

    for i in sorted(issues, key=lambda i: (i.priority, i.number)):
        if i.key in acted:
            continue
        links = [("Issue", i.url)] + ([("Why", i.reason_url)] if i.reason_url else []) \
            + [(f"PR #{p.number}", p.url) for p in i.prs]
        if i.status == "blocked":
            if i.protected_hold and not i.prs and not i.approved:
                out.append(Action("unblock", "Protected change waits for your approval",
                                  "comment the approval marker on the issue to let push-protected push",
                                  i.key, i.url, links, copy=APPROVE_MARKER))
            else:
                out.append(Action("unblock", "Blocked: answer the ask", "factory:blocked", i.key, i.url, links))
        elif "needs-scott" in i.labels:
            out.append(Action("unblock", "Needs you", "labelled needs-scott", i.key, i.url, links))
        elif "needs-target" in i.labels:
            out.append(Action("triage", "Name the target repo", "needs-target", i.key, i.url, links))
        else:
            continue  # the triage queue is shown as a count, not one action per issue
        out[-1].subject = i.title
    return out


def build_view(snapshots: dict[str, dict], errors: list[tuple[str, str]], approver: str,
               now: datetime | None = None, local: list[dict] | None = None) -> View:
    now = now or datetime.now(timezone.utc)
    issues: list[Issue] = []
    prs: list[PR] = []
    for repo, snap in snapshots.items():
        required = required_checks(((snap.get("factoryYml") or {}).get("text")))
        prs += [build_pr(repo, p, required, approver) for p in nodes(snap, "pullRequests")]
        issues += [build_issue(repo, i, approver) for i in nodes(snap, "issues")]
    by_key = {i.key: i for i in issues}
    for pr in prs:
        for r, n in pr.issues:
            if f"{r}#{n}" in by_key:
                by_key[f"{r}#{n}"].prs.append(pr)

    def order(i: Issue):
        return (not i.flagged, i.priority, i.number)

    board = {s: sorted([i for i in issues if i.status == s], key=order) for s in STATUSES}
    stale = [i for i in issues if i.status in STALE_STATUSES and i.since
             and (now - i.since).total_seconds() > STALE_DAYS * 86400]
    return View(
        now=now,
        repos=list(snapshots),
        errors=errors,
        issues=issues,
        prs=sorted(prs, key=lambda p: (p.repo, p.number)),
        actions=actions_for(issues, prs),
        running=sorted([i for i in issues if i.status in ("building", "gate")], key=lambda i: i.since or now),
        pending_prs=[p for p in prs if p.checks == "pending"],
        board=board,
        unlabelled=sorted([i for i in issues if not i.statuses], key=lambda i: (i.repo, i.number)),
        multi=[i for i in issues if len(i.statuses) > 1],
        stale=sorted(stale, key=lambda i: i.since),
        local=local or [],
    )


def age(now: datetime, then: datetime | None) -> str:
    if not then:
        return ""
    s = int((now - then).total_seconds())
    if s < 3600:
        return f"{max(s // 60, 0)}m"
    if s < 86400:
        return f"{s // 3600}h"
    return f"{s // 86400}d"
