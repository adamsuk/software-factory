"""Tests for the read-only factory dashboard (python -m unittest discover tests)."""

from __future__ import annotations

import json
import os
import re
import tempfile
import time
import unittest
from datetime import datetime, timezone
from pathlib import Path

from dashboard import github, local, model, render

FIXTURE = Path(__file__).parent / "fixtures" / "dashboard" / "snapshot.json"
NOW = datetime(2026, 11, 26, tzinfo=timezone.utc)


def view() -> model.View:
    snap = json.loads(FIXTURE.read_text())
    return model.build_view({"acme/widgets": snap}, [], approver="owner", now=NOW)


class QueryTest(unittest.TestCase):
    def test_query_is_read_only(self):
        self.assertTrue(github.QUERY.strip().startswith("query("))
        self.assertNotIn("mutation", github.QUERY)

    def test_fetch_runs_only_gh_api_graphql(self):
        calls = []

        def runner(args):
            calls.append(args)
            return json.dumps({"data": {"repository": {"nameWithOwner": "a/b"}}})

        self.assertEqual(github.fetch_repo("a/b", runner)["nameWithOwner"], "a/b")
        self.assertEqual(calls[0][:2], ["api", "graphql"])

    def test_bad_repo_rejected(self):
        with self.assertRaises(ValueError):
            github.fetch_repo("a/b; rm -rf /", lambda a: "")

    def test_default_repos_match_triage_ask(self):
        src = (Path(__file__).parent.parent / "scripts" / "triage-ask.sh").read_text()
        block = re.search(r"DEFAULT_REPOS = \((.*?)\)", src, re.S).group(1)
        self.assertEqual(tuple(re.findall(r'"([^"]+)"', block)), github.DEFAULT_REPOS)

    def test_resolve_repos(self):
        env = dict(os.environ)
        try:
            os.environ["FACTORY_REPOS"] = "x/y z/w"
            self.assertEqual(github.resolve_repos(None), (["x/y", "z/w"], False))
            self.assertEqual(github.resolve_repos(["c/d"]), (["c/d"], False))
            del os.environ["FACTORY_REPOS"]
            os.environ["FACTORY_HOME_REPO"] = "h/r"
            self.assertEqual(github.resolve_repos(None), (["h/r", *github.DEFAULT_REPOS], True))
            os.environ["FACTORY_HOME_REPO"] = "adamsuk/viva"
            repos, _ = github.resolve_repos(None)
            self.assertEqual(repos[0], "adamsuk/viva")
            self.assertEqual(len(repos), len(set(repos)))
            self.assertIn("adamsuk/viva-skills", repos)
        finally:
            os.environ.clear()
            os.environ.update(env)


class ModelTest(unittest.TestCase):
    def setUp(self):
        self.v = view()
        self.issues = {i.number: i for i in self.v.issues}
        self.prs = {p.number: p for p in self.v.prs}

    def test_required_checks_parse(self):
        self.assertEqual(model.required_checks("required_checks:\n  - tests\n  - 'lint'  # x\nother: 1\n"),
                         ["tests", "lint"])
        self.assertIsNone(model.required_checks("agents: {}\n"))
        self.assertIsNone(model.required_checks(None))

    def test_protected_paths(self):
        for p in (".github/workflows/ci.yml", "AGENTS.md", "agents/roles/x.md", "web/yarn.lock", "Cargo.lock"):
            self.assertTrue(model.is_protected(p), p)
        for p in ("agents/work-orders/a_b-1.md", "src/a.py", "docs/AGENTS.md.txt"):
            self.assertFalse(model.is_protected(p), p)

    def test_board_columns(self):
        self.assertEqual([i.number for i in self.v.board["blocked"]], [1, 6])  # P1 before unprioritised
        self.assertEqual([i.number for i in self.v.board["building"]], [2])
        self.assertEqual([i.number for i in self.v.board["triage"]], [5])
        self.assertEqual([i.number for i in self.v.board["review"]], [7])

    def test_time_in_state_from_label_event(self):
        self.assertEqual(self.issues[2].since, datetime(2026, 11, 20, tzinfo=timezone.utc))
        self.assertEqual(model.age(NOW, self.issues[2].since), "6d")

    def test_checks_required_only_and_pending_wins(self):
        self.assertEqual(self.prs[10].checks, "pending")  # lint failing but tests running
        self.assertEqual(self.prs[11].checks, "green")  # optional failure ignored
        self.assertEqual(self.prs[12].checks, "failing")
        self.assertEqual(self.prs[12].failing, ["tests"])

    def test_checks_without_required_list_judge_everything(self):
        st, _ = model.classify_checks([{"__typename": "CheckRun", "name": "x", "status": "COMPLETED",
                                        "conclusion": "FAILURE"}], None)
        self.assertEqual(st, "failing")
        self.assertEqual(model.classify_checks([], None)[0], "none")
        self.assertEqual(model.classify_checks([], ["tests"])[0], "pending")

    def test_pr_verdicts(self):
        self.assertEqual(self.prs[10].verdict, "pending")
        self.assertEqual(self.prs[11].verdict, "ready")
        self.assertEqual(self.prs[12].verdict, "failing-ci")
        self.assertEqual(model.pr_verdict("green", 2, [], "h"), "open-threads")
        self.assertEqual(model.pr_verdict("green", 0, [{"state": "CHANGES_REQUESTED", "commit": {"oid": "h"}}], "h"),
                         "changes-requested")
        old = [{"state": "APPROVED", "commit": {"oid": "old"}}]
        self.assertEqual(model.pr_verdict("green", 0, old, "h"), "needs-review")

    def test_independent_review_trusted_latest_on_head(self):
        # Latest trusted comment wins (PASS, older format); mallory's ESCALATE is ignored.
        self.assertEqual(self.prs[11].ir_verdict, "PASS")
        self.assertEqual(self.prs[10].ir_verdict, "none")

    def test_blocked_reason_only_from_trusted_marker(self):
        self.assertTrue(self.issues[1].reason_url.endswith("#c-real"))

    def test_protected_files_skip_work_orders(self):
        self.assertEqual(self.prs[10].protected_files, [])
        self.assertEqual(self.prs[11].protected_files, [".github/workflows/ci.yml"])

    def test_actions(self):
        acts = {(a.key, a.title) for a in self.v.actions}
        self.assertIn(("acme/widgets#11", "Ready for your approval"), acts)
        self.assertIn(("acme/widgets#12", "Dependabot PR failing CI"), acts)
        self.assertIn(("acme/widgets#1", "Blocked: answer the ask"), acts)
        self.assertIn(("acme/widgets#6", "Protected change waits for your approval"), acts)
        self.assertIn(("acme/widgets#5", "Name the target repo"), acts)
        # Issue 7 is covered by its PR's action; the pending PR 10 needs nobody.
        keys = [a.key for a in self.v.actions]
        self.assertNotIn("acme/widgets#7", keys)
        self.assertNotIn("acme/widgets#10", keys)
        held = next(a for a in self.v.actions if a.key == "acme/widgets#6")
        self.assertEqual(held.copy, model.APPROVE_MARKER)

    def test_actions_priority_order_repo_and_stage(self):
        unblock = [a for a in self.v.actions if a.group == "unblock"]
        # P1 first, then unprioritised by repo and number.
        self.assertEqual([a.number for a in unblock], [1, 6, 12])
        first = unblock[0]
        self.assertEqual((first.repo, first.stage, first.priority), ("acme/widgets", "blocked", 1))
        dep = unblock[-1]
        self.assertEqual((dep.stage, dep.priority), ("no linked issue", 4))
        pr = next(a for a in self.v.actions if a.number == 11)
        self.assertEqual(pr.stage, "review")  # a PR action takes its linked issue's stage

    def test_flagged_action_comes_first(self):
        snap = json.loads(FIXTURE.read_text())
        six = snap["issues"]["nodes"][5]
        six["labels"]["nodes"].append({"name": "priority: next"})
        v = model.build_view({"acme/widgets": snap}, [], approver="owner", now=NOW)
        unblock = [a for a in v.actions if a.group == "unblock"]
        self.assertEqual([a.number for a in unblock], [6, 1, 12])
        self.assertTrue(unblock[0].flagged)

    def test_escalate_and_failing_draft(self):
        snap = json.loads(FIXTURE.read_text())
        pr10 = snap["pullRequests"]["nodes"][0]
        pr10["isDraft"] = True
        pr10["commits"]["nodes"][0]["commit"]["statusCheckRollup"]["contexts"]["nodes"][0].update(
            status="COMPLETED", conclusion="FAILURE")
        pr11 = snap["pullRequests"]["nodes"][1]
        pr11["comments"]["nodes"].append({"author": {"login": "owner"}, "createdAt": "2026-11-25T02:00:00Z", "url": "",
                                          "body": "<!-- factory:independent-review v2 sha=bbbbbbb2222 -->\n"
                                                  "**Independent review (after CodeRabbit): ESCALATE** on bbbbbbb"})
        v = model.build_view({"acme/widgets": snap}, [], approver="owner", now=NOW)
        titles = {a.key: a.title for a in v.actions}
        self.assertEqual(titles["acme/widgets#10"], "Blocked by failing CI")
        self.assertEqual(titles["acme/widgets#11"], "Escalated by the independent review")

    def test_running_and_hygiene(self):
        self.assertEqual([i.number for i in self.v.running], [2])
        self.assertEqual([p.number for p in self.v.pending_prs], [10])
        self.assertEqual([i.number for i in self.v.multi], [3])
        self.assertEqual([i.number for i in self.v.unlabelled], [4])
        self.assertEqual([i.number for i in self.v.stale], [2])  # building for 6 days; review for 1 is fine


class RenderTest(unittest.TestCase):
    def test_untrusted_text_is_escaped(self):
        html = render.render(view())
        self.assertNotIn("<script>alert(1)</script>", html)
        self.assertIn("&lt;script&gt;alert(1)&lt;/script&gt;", html)

    def test_action_rows_show_repo_stage_and_priority(self):
        html = render.render(view())
        row = html[html.index("Blocked: answer the ask") - 400:html.index("Blocked: answer the ask")]
        self.assertIn('<span class="repo">acme/widgets</span>', row)
        self.assertIn(">blocked</span>", row)
        self.assertIn(">P1</span>", row)

    def test_every_action_group_is_split_by_repo(self):
        snap = json.loads(FIXTURE.read_text())
        other = json.loads(FIXTURE.read_text())
        other["nameWithOwner"] = "acme/alpha"
        v = model.build_view({"acme/widgets": snap, "acme/alpha": other}, [], approver="owner", now=NOW)
        html = render.render(v)
        review = html[html.index("Review and merge"):html.index("Decide")]
        heads = [h.split("<")[0].strip() for h in review.split('<h4 class="repo-head">')[1:]]
        self.assertEqual(heads, ["acme/alpha", "acme/widgets"])
        unblock = html[html.index("Unblock"):html.index("Review and merge")]
        heads = [h.split("<")[0].strip() for h in unblock.split('<h4 class="repo-head">')[1:]]
        self.assertEqual(heads, ["acme/alpha", "acme/widgets"])
        decide = html[html.index("Decide ("):html.index("Running now")]
        heads = [h.split("<")[0].strip() for h in decide.split('<h4 class="repo-head">')[1:]]
        self.assertEqual(heads, ["acme/alpha", "acme/widgets"])

    def test_only_github_links(self):
        self.assertEqual(render.safe_url("javascript:alert(1)"), "#")
        self.assertEqual(render.safe_url("https://evil.example/x"), "#")
        self.assertEqual(render.safe_url("https://github.com/a/b"), "https://github.com/a/b")

    def test_sections_and_refresh(self):
        html = render.render(view(), refresh=30)
        for s in ("Your actions", "Running now", "Pipeline", "Hygiene", "Open pull requests"):
            self.assertIn(s, html)
        self.assertIn('http-equiv="refresh" content="30"', html)
        self.assertNotIn("http-equiv", render.render(view()))

    def test_errors_shown(self):
        v = model.build_view({}, [("a/b", "HTTP 404 <b>")], approver="o", now=NOW)
        html = render.render(v)
        self.assertIn("a/b: HTTP 404 &lt;b&gt;", html)
        self.assertIn("Nothing needs you right now.", html)


class LocalTest(unittest.TestCase):
    def test_recent_clones_only(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / "wo-acme_widgets-2-Ab12Cd").mkdir()
            (root / "wo-acme_widgets-2-Ab12Cd.fenced-order.md").write_text("x")
            old = root / "wo-acme_widgets-1-Zz99Yy"
            old.mkdir()
            os.utime(old, (time.time() - 3 * 86400,) * 2)
            (root / "unrelated").mkdir()
            got = local.clones(root)
        self.assertEqual([(c["repo"], c["issue"]) for c in got], [("acme/widgets", 2)])

    def test_station_processes(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "4242"
            p.mkdir()
            (p / "cmdline").write_bytes(b"bash\0scripts/run-work-order.sh\0agents/work-orders/acme_widgets-9.md\0")
            q = Path(d) / "4243"
            q.mkdir()
            (q / "cmdline").write_bytes(b"vim\0scripts/run-work-order.sh\0")
            got = local.processes(Path(d))
        self.assertEqual(got, [{"kind": "process", "pid": 4242, "what": "run-work-order",
                                "repo": "acme/widgets", "issue": 9}])


if __name__ == "__main__":
    unittest.main()
