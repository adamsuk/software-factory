"""Factory runs on this machine: station processes and recent build clones.

Builds run on the maintainer's machine, not the watcher host, so this is
the only place a live build shows up. Reads /proc and directory names only;
never reads clone contents or process environments.
"""

from __future__ import annotations

import os
import re
import time
from pathlib import Path

STATION_RE = re.compile(r"scripts/(station-run|run-work-order|foreman-orchestrate|gate-issue|review-issue)\.sh")
ORDER_RE = re.compile(r"agents/work-orders/([A-Za-z0-9_.-]+?)_([A-Za-z0-9_.-]+)-(\d+)\.md")
CLONE_RE = re.compile(r"^wo-([A-Za-z0-9_.-]+?)_([A-Za-z0-9_.-]+)-(\d+)-[A-Za-z0-9]+$")
RECENT_SECONDS = 24 * 3600


def workspace() -> Path:
    home = os.environ.get("FACTORY_HOME") or os.path.join(
        os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "software-factory")
    return Path(os.environ.get("FACTORY_WORKSPACE") or home)


def processes(proc: Path = Path("/proc")) -> list[dict]:
    out = []
    if not proc.is_dir():
        return out
    me = os.getpid()
    for d in proc.iterdir():
        if not d.name.isdigit() or int(d.name) == me:
            continue
        try:
            args = (d / "cmdline").read_bytes().split(b"\0")
        except OSError:
            continue
        argv = [a.decode(errors="replace") for a in args if a]
        if not argv or not argv[0].endswith(("bash", "sh")):
            continue
        script = next((m.group(1) for a in argv[1:3] if (m := STATION_RE.search(a))), None)
        if not script:
            continue
        joined = " ".join(argv)
        m = ORDER_RE.search(joined)
        out.append({
            "kind": "process", "pid": int(d.name), "what": script,
            "repo": f"{m.group(1)}/{m.group(2)}" if m else "", "issue": int(m.group(3)) if m else None,
        })
    return out


def clones(root: Path | None = None, now: float | None = None) -> list[dict]:
    root = root or workspace()
    now = now or time.time()
    out = []
    if not root.is_dir():
        return out
    for d in root.iterdir():
        m = CLONE_RE.match(d.name)
        if not m or not d.is_dir():
            continue
        mtime = d.stat().st_mtime
        if now - mtime > RECENT_SECONDS:
            continue
        out.append({"kind": "clone", "path": str(d), "repo": f"{m.group(1)}/{m.group(2)}",
                    "issue": int(m.group(3)), "age_s": int(now - mtime)})
    return sorted(out, key=lambda c: c["age_s"])


def scan() -> list[dict]:
    return processes() + clones()
