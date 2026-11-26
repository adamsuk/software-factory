"""HTML for the dashboard. Every value goes through esc(): issue and PR text is untrusted."""

from __future__ import annotations

from html import escape
from urllib.parse import urlparse

from .model import PR, STATUSES, Action, Issue, View, age


def esc(v: object) -> str:
    return escape(str(v), quote=True)


def safe_url(u: str) -> str:
    """Only https links to github.com make it into an href."""
    p = urlparse(u or "")
    return esc(u) if p.scheme == "https" and p.hostname in ("github.com", "www.github.com") else "#"


def link(text: str, url: str, cls: str = "") -> str:
    c = f' class="{cls}"' if cls else ""
    return f'<a{c} href="{safe_url(url)}" target="_blank" rel="noopener noreferrer">{esc(text)}</a>'


CHIP = {
    "green": "ok", "ready": "ok", "PASS": "ok",
    "pending": "wait", "needs-review": "wait", "none": "muted",
    "failing": "bad", "failing-ci": "bad", "ESCALATE": "bad", "changes-requested": "bad",
    "open-threads": "warn", "FIX": "warn",
}


def chip(text: str, kind: str | None = None) -> str:
    return f'<span class="chip {CHIP.get(text, kind or "muted")}">{esc(text)}</span>'


def pr_chips(pr: PR) -> str:
    out = [chip(f"CI {pr.checks}", CHIP.get(pr.checks)), chip(pr.verdict)]
    if pr.ir_verdict != "none":
        out.append(chip(f"IR {pr.ir_verdict}", CHIP.get(pr.ir_verdict)))
    if pr.protected:
        out.append(chip("protected", "warn"))
    if pr.draft:
        out.append(chip("draft", "muted"))
    return " ".join(out)


def prio(i: Issue) -> str:
    out = []
    if i.flagged:
        out.append(chip("next", "accent"))
    if i.priority < 4:
        out.append(chip(f"P{i.priority}", "bad" if i.priority == 0 else "accent"))
    return " ".join(out)


STAGE_CHIP = {"blocked": "bad", "building": "wait", "gate": "wait", "review": "ok", "merge": "ok",
              "release": "ok", "triage": "muted", "ready": "accent"}


def action_row(a: Action) -> str:
    links = " ".join(link(t, u, "btn") for t, u in a.links)
    copy = ""
    if a.copy:
        copy = f'<button class="btn copy" type="button" data-copy="{esc(a.copy)}">Copy approval marker</button>'
    tags = [f'<span class="repo">{esc(a.repo)}</span>', chip(a.stage, STAGE_CHIP.get(a.stage, "muted"))]
    if a.flagged:
        tags.append(chip("next", "accent"))
    tags.append(chip(f"P{a.priority}", "bad" if a.priority == 0 else "accent") if a.priority < 4 else chip("no priority"))
    kind = "PR" if "/pull/" in a.url else "Issue"
    return (f'<li class="action {esc(a.group)}"><div class="what"><div class="tags">{" ".join(tags)}</div>'
            f'<strong>{esc(a.title)}</strong> {link(f"{kind} #{a.number}", a.url, "key")}'
            f'<div class="subject">{esc(a.subject)}</div>'
            f'<div class="why">{esc(a.why)}</div></div>'
            f'<div class="links">{links}{copy}</div></li>')


def issue_card(i: Issue, now) -> str:
    prs = "".join(f'<div class="sub">{link(f"PR #{p.number}", p.url)} {pr_chips(p)}</div>' for p in i.prs)
    return (f'<div class="card"><div class="top">{link(i.key, i.url, "key")} '
            f'<span class="age" title="time in this state">{esc(age(now, i.since))}</span> {prio(i)}</div>'
            f'<div class="title">{esc(i.title)}</div>{prs}</div>')


GROUPS = [("unblock", "Unblock"), ("review", "Review and merge"), ("triage", "Decide")]

CSS = """
:root{--bg:#f6f7f9;--panel:#fff;--fg:#1c2330;--muted:#677284;--line:#e2e6ec;--accent:#3b5bdb;
--ok:#2b8a3e;--okbg:#e6f4ea;--warn:#b35c00;--warnbg:#fff1e0;--bad:#c92a2a;--badbg:#fdeaea;--waitbg:#eef1fb}
@media (prefers-color-scheme:dark){:root{--bg:#12151b;--panel:#1a1f27;--fg:#e4e8ef;--muted:#8d97a8;--line:#2b323d;
--accent:#8ea6ff;--ok:#69db7c;--okbg:#1b3324;--warn:#ffb46b;--warnbg:#3a2a17;--bad:#ff8787;--badbg:#3d1d1f;--waitbg:#232a3b}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.45 system-ui,sans-serif}
header{display:flex;flex-wrap:wrap;gap:12px;align-items:baseline;padding:16px 20px;border-bottom:1px solid var(--line);background:var(--panel)}
header h1{font-size:18px;margin:0}header .meta{color:var(--muted);font-size:12px}main{padding:16px 20px;display:grid;gap:18px}
section{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:14px 16px}
h2{font-size:15px;margin:0 0 10px;display:flex;gap:8px;align-items:center}h3{font-size:12px;text-transform:uppercase;letter-spacing:.04em;color:var(--muted);margin:12px 0 6px}
.badge{background:var(--accent);color:#fff;border-radius:999px;padding:0 8px;font-size:12px}
ul{list-style:none;margin:0;padding:0}.action{display:flex;flex-wrap:wrap;justify-content:space-between;gap:8px;padding:8px 0;border-top:1px solid var(--line)}
.action:first-child{border-top:0}.action.unblock{border-left:3px solid var(--bad);padding-left:10px}.action.review{border-left:3px solid var(--ok);padding-left:10px}
.action.triage{border-left:3px solid var(--accent);padding-left:10px}.why{color:var(--muted);font-size:12px}.subject{overflow-wrap:anywhere}.tags{display:flex;flex-wrap:wrap;gap:4px;align-items:center;margin-bottom:2px}.repo{font-family:ui-monospace,monospace;font-size:11px;font-weight:600;border:1px solid var(--line);border-radius:4px;padding:0 6px}.what{min-width:0;flex:1 1 320px}.links{display:flex;gap:6px;flex-wrap:wrap;align-items:center}
a{color:var(--accent);text-decoration:none}a:hover{text-decoration:underline}a.key{font-family:ui-monospace,monospace;font-size:12px}
.btn{border:1px solid var(--line);border-radius:6px;padding:2px 8px;font-size:12px;background:var(--bg);color:var(--fg);cursor:pointer}
.chip{display:inline-block;border-radius:4px;padding:0 6px;font-size:11px;background:var(--line);color:var(--muted)}
.chip.ok{background:var(--okbg);color:var(--ok)}.chip.bad{background:var(--badbg);color:var(--bad)}.chip.warn{background:var(--warnbg);color:var(--warn)}
.chip.wait{background:var(--waitbg);color:var(--accent)}.chip.accent{background:var(--accent);color:#fff}
.board{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:10px}.col{background:var(--bg);border-radius:8px;padding:8px;min-height:60px}
.col h3{margin:0 0 6px;display:flex;justify-content:space-between}.card{background:var(--panel);border:1px solid var(--line);border-radius:6px;padding:6px 8px;margin-bottom:6px}
.card .title{font-size:13px;overflow-wrap:anywhere}.card .sub{margin-top:4px;font-size:12px}.age{color:var(--muted);font-size:11px}
table{width:100%;border-collapse:collapse}td,th{text-align:left;padding:5px 6px;border-top:1px solid var(--line);font-size:13px;vertical-align:top}
th{color:var(--muted);font-weight:600;font-size:12px}.empty{color:var(--muted);font-size:13px}.err{color:var(--bad)}
details summary{cursor:pointer;color:var(--muted)}.grid2{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:18px}
"""

JS = """
document.addEventListener('click',e=>{const b=e.target.closest('.copy');if(!b)return;
navigator.clipboard.writeText(b.dataset.copy).then(()=>{b.textContent='Copied';setTimeout(()=>b.textContent='Copy approval marker',1500)})});
"""


def render(v: View, refresh: int | None = None) -> str:
    now = v.now
    meta = f'<meta http-equiv="refresh" content="{int(refresh)}">' if refresh else ""
    errs = "".join(f'<div class="err">{esc(r)}: {esc(e)}</div>' for r, e in v.errors)

    # Your actions
    parts = []
    for g, label in GROUPS:
        rows = [a for a in v.actions if a.group == g]
        if rows:
            parts.append(f"<h3>{esc(label)} ({len(rows)})</h3><ul>{''.join(action_row(a) for a in rows)}</ul>")
    triage = len(v.board["triage"])
    if triage:
        parts.append(f'<h3>Triage queue</h3><div class="empty">{triage} issue(s) in factory:triage, '
                     f'handled by intake. See the board below.</div>')
    actions = "".join(parts) or '<div class="empty">Nothing needs you right now.</div>'

    # Running now
    run_rows = "".join(
        f'<tr><td>{link(i.key, i.url, "key")}</td><td>{chip(i.status or "")}</td><td>{esc(age(now, i.since))}</td>'
        f'<td>{esc(i.title)}{"".join("<br>" + link(f"PR #{p.number}", p.url) + " " + pr_chips(p) for p in i.prs)}</td></tr>'
        for i in v.running)
    pend = "".join(f'<tr><td>{link(p.key, p.url, "key")}</td><td>{chip("checks")}</td><td>{esc(age(now, p.updated))}</td>'
                   f'<td>{esc(p.title)} {pr_chips(p)}</td></tr>' for p in v.pending_prs if not any(p in i.prs for i in v.running))
    local = "".join(
        f'<tr><td>{esc(lr["repo"] + "#" + str(lr["issue"]) if lr.get("issue") else "")}</td><td>{chip("local " + lr["kind"], "accent")}</td>'
        f'<td>{esc(age_s(lr.get("age_s")))}</td><td>{esc(lr.get("what") or lr.get("path") or "")}</td></tr>' for lr in v.local)
    running = (f"<table><tr><th>Item</th><th>State</th><th>For</th><th></th></tr>{run_rows}{pend}{local}</table>"
               if run_rows or pend or local else '<div class="empty">Nothing building, gating or checking.</div>')

    # Board
    cols = "".join(
        f'<div class="col"><h3><span>{esc(s)}</span><span>{len(v.board[s])}</span></h3>'
        f'{"".join(issue_card(i, now) for i in v.board[s][:40])}'
        f'{"<div class=empty>+" + str(len(v.board[s]) - 40) + " more</div>" if len(v.board[s]) > 40 else ""}</div>'
        for s in STATUSES if s != "done")

    # Open PRs
    pr_rows = "".join(f'<tr><td>{link(p.key, p.url, "key")}</td><td>{esc(p.title)}</td><td>{pr_chips(p)}</td>'
                      f'<td>{esc(p.author)}</td><td>{esc(age(now, p.updated))}</td></tr>' for p in v.prs)
    prs = (f"<table><tr><th>PR</th><th>Title</th><th>State</th><th>Author</th><th>Updated</th></tr>{pr_rows}</table>"
           if pr_rows else '<div class="empty">No open pull requests.</div>')

    # Hygiene
    def ilist(items: list[Issue], note: str) -> str:
        return "".join(f'<li>{link(i.key, i.url, "key")} {esc(i.title)} <span class="age">{esc(note(i) if callable(note) else note)}</span></li>'
                       for i in items)
    hyg = []
    if v.stale:
        hyg.append(f"<h3>Stale over 3 days ({len(v.stale)})</h3><ul>{ilist(v.stale, lambda i: (i.status or '') + ' for ' + age(now, i.since))}</ul>")
    if v.multi:
        hyg.append(f"<h3>More than one factory:* label ({len(v.multi)})</h3><ul>{ilist(v.multi, lambda i: ', '.join(i.statuses))}</ul>")
    if v.unlabelled:
        hyg.append(f"<details><summary>No factory:* label ({len(v.unlabelled)})</summary><ul>{ilist(v.unlabelled, '')}</ul></details>")
    hygiene = "".join(hyg) or '<div class="empty">Labels are clean.</div>'

    n = len([a for a in v.actions])
    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
{meta}<title>Factory dashboard</title><style>{CSS}</style></head><body>
<header><h1>Software factory</h1><span class="meta">{esc(", ".join(v.repos))} · updated {esc(v.now.strftime("%Y-%m-%d %H:%M UTC"))}{" · refreshes every " + str(int(refresh)) + "s" if refresh else ""}</span>{errs}</header>
<main>
<section><h2>Your actions <span class="badge">{n}</span></h2>{actions}</section>
<div class="grid2"><section><h2>Running now</h2>{running}</section><section><h2>Hygiene</h2>{hygiene}</section></div>
<section><h2>Pipeline</h2><div class="board">{cols}</div></section>
<section><h2>Open pull requests <span class="badge">{len(v.prs)}</span></h2>{prs}</section>
</main><script>{JS}</script></body></html>"""


def age_s(s: int | None) -> str:
    if s is None:
        return ""
    return f"{s // 60}m" if s < 3600 else f"{s // 3600}h"
