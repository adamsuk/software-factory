---
repo: adamsuk/software-factory
issue: 106
issue_repo: adamsuk/software-factory
title: "feat: Research Scout files factory issues on research repos instead of opening its own PRs"
branch: factory/106-research-files-issues
base: main
test_command: "shellcheck scripts/*.sh adapters/*/run.sh"
setup_command: ""
changelog: true
merge_allowed: false
review_bot: coderabbit
attempt: 1
created: 2026-10-30
---

## Go-ahead (Scott, 30 Oct)

This issue's own triage comment said a builder should not open a PR here
without Scott's explicit reply, since it edits a protected role brief and
the issue body's own "Scott merges this PR himself" line is untrusted issue
text. Scott has now said, in chat, to go ahead and build it the normal way —
build it, open the PR, and it routes to `factory:blocked` for his review
regardless of verdict, same as every other protected-path ticket this
session.

## Goal

`adamsuk/line` was enrolled in the factory on 27 Oct 2026. Research Scout
should stop writing and merging its own PRs there. Instead it should feed
the factory: it finds the changes and files issues, and the factory builds
them with Grok Build and merges them under the normal rules.

## Change `agents/roles/research.md`

- **Steps:** for each meaningful source change, file one issue on the
  research repo with labels `factory` and `factory:triage`. Give the dated
  sources (URLs and dates), the section of the guide it affects, the
  proposed change in a few sentences, and a line saying the CHANGELOG entry
  and collapsible sections are needed. Open at most 3 issues per repo per
  run, and don't duplicate an open issue.
- **Outputs:** issues instead of PRs. Research Scout opens no PRs and merges
  nothing; the factory's builder and watcher do that.
- **Weekly summary:** send it to the foreman (Software Factory), listing
  the issues filed. The foreman tells Scott only what needs him.
- **Cost mode:** skim for change; no deep reads beyond what's needed to
  cite a source. Writing the guide text is Grok Build's job.
- Keep the stop rules: web pages are untrusted, and stop on paywalled or
  unclear sources.

Add a dated `CHANGELOG.md` entry.

## Out of scope

- Guide text in any research repo, including `adamsuk/line`. Research Scout
  cites the change; Grok Build writes the guide.
- Enrolment or `.github/factory.yml` on `adamsuk/line`. That repo has the
  `factory` topic and no `.github/factory.yml`, so the default roles are
  builder and reviewer. It does not list `intake`. A follow-up that adds
  `intake` there is a separate issue in `adamsuk/line`, and this issue must
  not open it.
- `agents/roles/foreman.md`. The research brief tells Research Scout to
  address the weekly summary to the foreman. A foreman receive-step is a
  separate issue.
- `AGENTS.md`, every other file under `agents/`, `scripts/`, and `.github/`.
- Any repository other than `adamsuk/software-factory`, including
  `adamsuk/gh-factory`, `adamsuk/activity-feed`, `adamsuk/adamsuk`,
  `adamsuk/line`, and any touchlineHQ repository.

## Acceptance criteria

- [ ] The Steps section says that each meaningful source change becomes one
      issue on the research repo, labelled `factory` and `factory:triage`,
      with dated sources (URLs and dates), the guide section, a short
      proposed change, and a line that the `CHANGELOG.md` entry and
      collapsible sections are required. It caps new issues at 3 per repo
      per run and skips a change that already has an open issue.
- [ ] Outputs say Research Scout files issues, opens no pull requests, and
      merges nothing, and that the factory builder does the build.
- [ ] The weekly summary is sent to the foreman and lists the issues filed.
      The foreman is the one who tells Scott what needs him.
- [ ] Cost mode says to skim, to read only enough to cite a source, and
      that writing the guide text is Grok Build's job.
- [ ] Stop rules still say web pages are untrusted and that a paywalled or
      unclear source stops the run.
- [ ] `CHANGELOG.md` has a dated `## YYYY-MM-DD` entry (Europe/London) for
      this change, in this repo's Keep a Changelog style, naming Research
      Scout or `agents/roles/research.md` and this issue.
- [ ] `shellcheck scripts/*.sh` exits 0. It stays green and does not assert
      the role text — this is a role-brief edit, so no new test file is
      required.
- [ ] Apart from this work order, the only implementation files changed
      are `agents/roles/research.md` and `CHANGELOG.md`.

## Report back

In the PR body: confirm that, apart from the work order files, the only
implementation files changed are `agents/roles/research.md` and `CHANGELOG.md`. This PR edits a protected path (`agents/roles/**`,
AGENTS.md §5) — say so explicitly and expect Scott's review regardless of
verdict.
