"""python -m dashboard serve|render: the read-only factory dashboard."""

from __future__ import annotations

import argparse
import os
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from . import github, local, model, render

MAX_DISCOVERED = 10


def snapshot(repos: list[str], discover: bool) -> model.View:
    approver = os.environ.get("FACTORY_APPROVER_LOGIN") or (repos[0].split("/")[0] if repos else "")
    snaps: dict[str, dict] = {}
    errors: list[tuple[str, str]] = []

    def get(r: str):
        try:
            return r, github.fetch_repo(r), None
        except Exception as e:  # shown on the page, never fatal
            return r, None, str(e)

    with ThreadPoolExecutor(max_workers=6) as pool:
        for r, s, e in pool.map(get, repos):
            if s is not None:
                snaps[r] = s
            else:
                errors.append((r, e))
        if discover:
            found: list[str] = []
            for s in list(snaps.values()):
                for i in model.nodes(s, "issues"):
                    for t in github.TARGET_RE.findall(i.get("body") or ""):
                        if t not in snaps and t not in found and github.REPO_RE.match(t):
                            found.append(t)
            # Discovered repos come from issue text: any that can't be read are skipped quietly.
            for r, s, _ in pool.map(get, found[:MAX_DISCOVERED]):
                if s is not None:
                    snaps[r] = s
    return model.build_view(snaps, errors, approver, local=local.scan())


class Cache:
    def __init__(self, repos, discover, ttl):
        self.repos, self.discover, self.ttl = repos, discover, ttl
        self.lock = threading.Lock()
        self.at, self.html = 0.0, ""

    def page(self, force: bool, refresh: int) -> str:
        with self.lock:
            if force or not self.html or time.time() - self.at > self.ttl:
                self.html = render.render(snapshot(self.repos, self.discover), refresh=refresh)
                self.at = time.time()
            return self.html


def serve(args, repos, discover) -> None:
    cache = Cache(repos, discover, args.ttl)

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            path, _, query = self.path.partition("?")
            if path != "/":
                self.send_error(404)
                return
            body = cache.page("refresh=1" in query, args.refresh).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Security-Policy",
                             "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, fmt, *a):
            pass

    httpd = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"factory dashboard on http://127.0.0.1:{args.port}/ ({', '.join(repos)})", flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="python -m dashboard", description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("serve", "render"):
        sp = sub.add_parser(name)
        sp.add_argument("--repo", action="append", help="owner/repo; repeatable (default FACTORY_REPOS, "
                        "else FACTORY_HOME_REPO plus the target repos its open issues name)")
    sub.choices["serve"].add_argument("--port", type=int, default=8787)
    sub.choices["serve"].add_argument("--ttl", type=int, default=60, help="seconds to cache GitHub reads")
    sub.choices["serve"].add_argument("--refresh", type=int, default=60, help="page auto-refresh seconds")
    sub.choices["render"].add_argument("--out", required=True, help="HTML file to write")
    args = p.parse_args(argv)

    repos, discover = github.resolve_repos(args.repo)
    bad = [r for r in repos if not github.REPO_RE.match(r)]
    if not repos or bad:
        p.error(f"bad or missing repo: {' '.join(bad) or 'pass --repo or set FACTORY_REPOS'}")
    if args.cmd == "serve":
        serve(args, repos, discover)
        return 0
    view = snapshot(repos, discover)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(render.render(view))
    print(f"wrote {args.out}: {len(view.actions)} action(s), {len(view.running)} running, "
          f"{len(view.errors)} error(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
