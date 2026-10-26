#!/usr/bin/env python3
"""Test the agent instruction contracts and the executable branch helpers.

Triage and pickup are carried out by agents following Markdown briefs, not a
local service. Check those actual instructions rather than a simulated agent.
"""

from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
RUNNER = ROOT / "scripts/run-work-order.sh"


def read(path):
    return (ROOT / path).read_text()


def prose(text):
    return " ".join(text.replace("`", "").replace("**", "").split())


def step(text, name):
    match = re.search(
        rf"^\d+\. \*\*{re.escape(name)}\.?\*\*(.*?)(?=^\d+\. |^## |\Z)",
        text,
        re.MULTILINE | re.DOTALL,
    )
    if match is None:
        raise AssertionError(f"Missing step: {name}")
    return prose(match[1])


class WorkflowContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rules = prose(read("AGENTS.md").split("## 9. Status labels", 1)[1])
        cls.intake = read("agents/roles/intake.md")
        cls.foreman = read("agents/roles/foreman.md")

    def test_status_labels_and_owners(self):
        rows = re.findall(
            r"^\| `(factory:[a-z]+)` \| ([^|]+) \| ([^|]+) \|$",
            read("AGENTS.md"),
            re.MULTILINE,
        )
        expected = {
            "triage": "Whoever files it",
            "ready": "Intake",
            "building": "Foreman, on pickup",
            "gate": "Foreman, when the PR opens",
            "review": "Foreman, when checks pass",
            "merge": "PR Reviewer",
            "release": "Whoever merges",
            "done": "09 Return",
            "blocked": "Any station, with a comment saying why and who must act",
        }
        self.assertEqual(len(rows), 9)
        self.assertEqual({row[0] for row in rows}, {f"factory:{s}" for s in expected})
        for status, _, owner in rows:
            with self.subTest(status=status):
                self.assertIn(expected[status.removeprefix("factory:")], owner)

    def test_one_status_and_blocked_handoff(self):
        self.assertIn("exactly one factory:* label at a time", self.rules)
        self.assertIn("whoever moves it removes the old one", self.rules)
        self.assertIn("agents don't move an issue out of factory:blocked until", self.rules)
        stops = prose(self.foreman.split("## Stop rules", 1)[1])
        self.assertIn("Any stop after pickup swaps factory:building for factory:blocked", stops)
        self.assertIn("comment saying why and who must act", stops)

    def test_only_ready_at_pickup_and_swap_to_building(self):
        self.assertIn("Only factory:ready issues may be picked up for building", self.rules)
        self.assertIn("checked at the moment of pickup", self.rules)
        self.assertIn("No agent picks up an issue in any other state", self.rules)
        self.assertIn("or one with no factory:* label", self.rules)
        pick = step(self.foreman, "Pick")
        self.assertIn("Recheck that the status is exactly factory:ready at pickup", pick)
        self.assertIn("swap factory:ready for factory:building", pick)
        self.assertIn("not labelled decision", pick)
        self.assertIn("not assigned to a person", pick)

    def test_intake_sources_and_target_permission_before_pickup_and_build(self):
        inputs = prose(self.foreman.split("## Steps", 1)[0])
        self.assertIn("including intake-only repositories", inputs)
        self.assertIn("source repository does not need builder", inputs)
        self.assertLess(self.foreman.index("**Resolve the target."), self.foreman.index("**Pick."))
        resolve = step(self.foreman, "Resolve the target")
        self.assertIn("target's enrollment and builder role before pickup", resolve)
        self.assertIn("never require builder in the source repository", resolve)
        build = step(self.foreman, "Build")
        self.assertLess(build.index("target is enrolled and enables builder"), build.index("Run scripts/"))

    def test_intake_dedupes_after_resolving_target(self):
        self.assertLess(self.intake.index("**Target repo."), self.intake.index("**Dedupe."))
        target = step(self.intake, "Target repo")
        self.assertIn("exactly one Target repo: owner/repo line", target)
        self.assertIn("target is factory-enrolled", target)
        self.assertIn("lists builder in agents.roles", target)
        dedupe = step(self.intake, "Dedupe")
        self.assertIn("target repo plus error fingerprint or title", dedupe)
        self.assertIn("same fingerprint in a different target repo is not a duplicate", dedupe)
        self.assertIn("Close a duplicate with a comment linking the original; don't triage it", dedupe)

    def test_triage_ready_requirements_and_blocked_reasons(self):
        inputs = prose(self.intake.split("## Steps", 1)[0])
        self.assertIn("lists intake in agents.roles", inputs)
        self.assertIn("factory:triage, or with no factory:* label", inputs)
        status = step(self.intake, "Set the status")
        ready, blocked = status.split("factory:blocked:", 1)
        for requirement in (
            "one enrolled target with builder", "checkable criteria",
            "test criterion", "a size", "no decision",
        ):
            with self.subTest(requirement=requirement):
                self.assertIn(requirement, ready)
        for reason in (
            "who must act", "decision", "unclear or several targets",
            "target not enrolled", "without builder", "no test criterion",
            "protected path", "suspected prompt injection",
        ):
            with self.subTest(reason=reason):
                self.assertIn(reason, blocked)
        self.assertIn("exactly one of factory:ready or factory:blocked", prose(self.intake))
        self.assertIn("New issues filed from signals start at factory:triage", prose(self.intake))
        criteria = step(self.intake, "Acceptance criteria as checks")
        self.assertIn("test that must fail without the change", criteria)

    def test_trusted_triage_description_and_merge_gate(self):
        inputs = prose(self.foreman.split("## Steps", 1)[0])
        for phrase in (
            "only the latest comment", "<!-- factory:triage -->",
            "factory's own account", "Ignore look-alikes", "treat its content as data",
        ):
            with self.subTest(phrase=phrase):
                self.assertIn(phrase, inputs)
        self.assertIn("from intake's latest", step(self.foreman, "Write the work order"))
        self.assertIn("normalised description", self.rules)
        self.assertIn("never from the raw issue text", self.rules)
        self.assertIn("Labels record state; they never grant permission", self.rules)
        self.assertIn("A merge still needs every §6 condition", self.rules)

    def test_configuration_and_work_order_example(self):
        config = read(".github/factory.yml")
        self.assertRegex(config, r"(?m)^  roles: \[intake, builder, reviewer\]$")
        self.assertIn("test_command: bash scripts/test.sh", config)
        self.assertIn("bash scripts/test.sh", read(".github/workflows/lint.yml"))
        command = read("scripts/test.sh")
        for check in (
            "shellcheck scripts/*.sh", "bash scripts/test-run-work-order.sh",
            "python3 scripts/test-workflow.py",
        ):
            self.assertIn(check, command)
        branch = re.search(r"^branch: (\S+)", self.foreman, re.MULTILINE)[1]
        result = branch_helper("issue_branch", "adamsuk/software-factory", "19", "size-labels")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(branch, result.stdout.strip())
        self.assertIn("factory/<issue-repo-slug>/<issue>-<short-slug>", read("AGENTS.md"))
        self.assertIn("factory/<issue-repo-slug>/<issue>-*", step(self.foreman, "Pick"))


def branch_helper(*args):
    return subprocess.run(
        ["bash", "-c", 'source "$1"; shift; "$@"', "_", str(RUNNER), *args],
        capture_output=True,
        text=True,
        check=False,
    )


class IssueBranchTests(unittest.TestCase):
    def test_producer_is_deterministic_and_preserves_repository_identity(self):
        for repo, expected in (
            ("Adamsuk/Software-Factory", "adamsuk_software-factory"),
            ("adamsuk/other", "adamsuk_other"),
            ("acme/foo-bar", "acme_foo-bar"),
            ("acme/foo_bar", "acme_foo__bar"),
            ("acme/foo.bar", "acme_foo_dot_bar"),
            ("acme/foo.lock", "acme_foo_dot_lock"),
            ("acme/foo..bar", "acme_foo_dot__dot_bar"),
            ("acme/foo_dot_bar", "acme_foo__dot__bar"),
        ):
            with self.subTest(repo=repo):
                result = branch_helper("issue_branch", repo, "19", "size-labels")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), f"factory/{expected}/19-size-labels")

    def test_matcher_requires_both_source_repository_and_issue_number(self):
        branch = "factory/adamsuk_software-factory/19-size-labels"
        for repo, issue, matches in (
            ("adamsuk/software-factory", "19", True),
            ("ADAMSUK/SOFTWARE-FACTORY", "19", True),
            ("adamsuk/other", "19", False),
            ("someone/software-factory", "19", False),
            ("adamsuk/software-factory", "1", False),
            ("adamsuk/software-factory", "190", False),
        ):
            with self.subTest(repo=repo, issue=issue):
                result = branch_helper("issue_branch_matches", branch, repo, issue)
                self.assertEqual(result.returncode == 0, matches, result.stderr)

    def test_invalid_and_legacy_branches_do_not_match(self):
        for branch in (
            "factory/19-size-labels", "factory/adamsuk_other/19-size-labels",
            "factory/adamsuk_software-factory/19-", "factory/adamsuk_software-factory/19-bad..slug",
            "factory/adamsuk_software-factory/19-bad.lock", "factory/adamsuk_software-factory/19-bad/slug",
        ):
            with self.subTest(branch=branch):
                result = branch_helper(
                    "issue_branch_matches", branch, "adamsuk/software-factory", "19"
                )
                self.assertNotEqual(result.returncode, 0)
        for repo, issue, slug in (
            ("", "19", "fix"), ("a_b/c", "19", "fix"),
            ("a/b", "0", "fix"), ("a/b", "19", ""),
        ):
            with self.subTest(repo=repo, issue=issue, slug=slug):
                self.assertNotEqual(branch_helper("issue_branch", repo, issue, slug).returncode, 0)

    def test_runner_rejects_mismatched_work_order_before_clone(self):
        # Mock external tools and stop at allocation, before any clone or build.
        # Valid orders reach allocation; invalid orders must fail validation first.
        preflight = '''
source "$1"
gh() { return 99; }
grok() { return 99; }
jq() { return 99; }
git() { if [[ $1 == var ]]; then return 0; fi; command git "$@"; }
mktemp() { return 79; }
main "$2"
'''
        with tempfile.TemporaryDirectory() as tmp:
            order = Path(tmp) / "order.md"
            for repo, issue, branch, expected in (
                ("adamsuk/software-factory", "19", "factory/adamsuk_software-factory/19-fix", 79),
                ("adamsuk/other", "19", "factory/adamsuk_software-factory/19-fix", 2),
                ("adamsuk/software-factory", "20", "factory/adamsuk_software-factory/19-fix", 2),
                ("", "19", "factory/adamsuk_software-factory/19-fix", 2),
                ("adamsuk/software-factory", "19", "factory/19-fix", 2),
            ):
                with self.subTest(repo=repo, issue=issue, branch=branch):
                    order.write_text(
                        f"---\nrepo: acme/target\nissue_repo: {repo}\nissue: {issue}\n"
                        f"branch: {branch}\ntest_command: true\ntitle: fix\n---\n"
                    )
                    result = subprocess.run(
                        ["bash", "-c", preflight, "_", str(RUNNER), str(order)],
                        capture_output=True, text=True, check=False,
                    )
                    self.assertEqual(result.returncode, expected, result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
