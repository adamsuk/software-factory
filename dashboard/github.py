"""GitHub reads for the dashboard: one GraphQL query per repo through `gh`.

Read-only by construction: QUERY is a `query`, and `gh api graphql` is the
only gh command run. Uses the existing gh login; never reads token files
(AGENTS.md section 7).
"""

from __future__ import annotations

import json
import os
import re
import subprocess
from typing import Callable

REPO_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")

QUERY = """
query($owner: String!, $name: String!) {
  repository(owner: $owner, name: $name) {
    nameWithOwner
    url
    factoryYml: object(expression: "HEAD:.github/factory.yml") { ... on Blob { text } }
    issues(states: OPEN, first: 100, orderBy: {field: UPDATED_AT, direction: DESC}) {
      nodes {
        number title url body createdAt updatedAt
        labels(first: 30) { nodes { name } }
        comments(last: 20) { nodes { author { login } body url createdAt } }
        timelineItems(last: 30, itemTypes: [LABELED_EVENT]) {
          nodes { ... on LabeledEvent { createdAt label { name } } }
        }
      }
    }
    pullRequests(states: OPEN, first: 50, orderBy: {field: UPDATED_AT, direction: DESC}) {
      nodes {
        number title url isDraft createdAt updatedAt headRefName headRefOid mergeStateStatus
        author { login }
        labels(first: 30) { nodes { name } }
        files(first: 100) { nodes { path } }
        closingIssuesReferences(first: 5) { nodes { number repository { nameWithOwner } } }
        reviewThreads(first: 100) { nodes { isResolved } }
        latestReviews(first: 20) { nodes { author { login } state submittedAt commit { oid } } }
        comments(last: 30) { nodes { author { login } body url createdAt } }
        commits(last: 1) {
          nodes { commit { statusCheckRollup { contexts(first: 100) { nodes {
            __typename
            ... on CheckRun { name status conclusion detailsUrl }
            ... on StatusContext { context state targetUrl }
          } } } } }
        }
      }
    }
  }
}
"""

Runner = Callable[[list[str]], str]


def run_gh(args: list[str]) -> str:
    out = subprocess.run(["gh", *args], capture_output=True, text=True, timeout=60)
    if out.returncode != 0:
        raise RuntimeError((out.stderr or "gh failed").strip().splitlines()[-1][:200])
    return out.stdout


def fetch_repo(repo: str, runner: Runner = run_gh) -> dict:
    if not REPO_RE.match(repo):
        raise ValueError(f"bad repo: {repo}")
    owner, name = repo.split("/", 1)
    raw = runner(["api", "graphql", "-f", f"query={QUERY}", "-F", f"owner={owner}", "-F", f"name={name}"])
    data = json.loads(raw)
    if data.get("errors") and not (data.get("data") or {}).get("repository"):
        raise RuntimeError(str(data["errors"][0].get("message", "graphql error"))[:200])
    return data["data"]["repository"]


def _origin_repo() -> str:
    try:
        url = subprocess.run(["git", "remote", "get-url", "origin"], capture_output=True,
                             text=True, timeout=10).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""
    m = re.search(r"[:/]([^/:]+/[^/:]+?)(?:\.git)?/?$", url)
    return m.group(1) if m else ""


def home_repo() -> str:
    """FACTORY_HOME_REPO, then GITHUB_REPOSITORY, then the origin remote (as factory-flagged.sh)."""
    return os.environ.get("FACTORY_HOME_REPO") or os.environ.get("GITHUB_REPOSITORY") or _origin_repo()


# The factory's enrolled repos: the same list as DEFAULT_REPOS in
# scripts/triage-ask.sh (a test keeps the two in step). Used when neither
# --repo nor FACTORY_REPOS is given.
DEFAULT_REPOS = (
    "adamsuk/software-factory",
    "adamsuk/gh-factory",
    "adamsuk/activity-feed",
    "adamsuk/line",
    "adamsuk/adamsuk",
    "adamsuk/viva",
    "adamsuk/viva-skills",
)

TARGET_RE = re.compile(r"^Target repo:\s*`?([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)`?\s*$", re.M)


def resolve_repos(cli: list[str] | None) -> tuple[list[str], bool]:
    """Repos to show and whether to also add target repos named by their issues.

    --repo, then FACTORY_REPOS, are taken as given. Otherwise the home repo
    plus DEFAULT_REPOS, and any target repo their issues name.
    """
    if cli:
        return cli, False
    env = os.environ.get("FACTORY_REPOS", "").split()
    if env:
        return env, False
    home = home_repo()
    repos = [home] if home else []
    repos += [r for r in DEFAULT_REPOS if r not in repos]
    return repos, True
