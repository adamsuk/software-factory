# Running a ticket through the factory

This repo (`adamsuk/software-factory`) already defines its own pipeline —
`AGENTS.md`, `stations/README.md`, and the scripts under `scripts/` are the
canonical rules, and they're deliberately provider-agnostic (`grok`,
`opencode`, `claudecode`, or none at all — a person just running the
scripts by hand). This doc does not replace them; it is the muscle memory
for driving them, so each run doesn't have to rediscover identity quirks,
missing-paperwork gaps, and merge-conflict edge cases through trial and
error the way the first few runs did. It's written to be followed by any
agent operating this repo, or by a person doing the same steps by hand —
nothing below assumes a particular tool. (If you're using Claude Code,
there's also a thin skill at `.claude/skills/run-factory/SKILL.md` that
just points back here, so this stays the one copy of the actual content.)

**Core discipline: only ever act through this repo's own scripts, never by
hand-editing a label or calling `gh issue edit` / `gh pr create` / `gh pr
merge` directly as a substitute for what a station script already does.**
The one deliberate exception is small, non-protected mechanical fixes
(a merge conflict confined to `CHANGELOG.md`, a missing work-order file,
a one-line CodeRabbit nit) — those are called out explicitly below, because
they're bookkeeping a station *should* have done, not a judgment call.

**Narrate as you go.** Before each station run, say one line: which station,
on which issue/PR, and why. Whoever is directing this work shouldn't have to
re-explain the pipeline's mechanics every time — the narration is what
replaces that re-explanation.

**Ask, don't guess, at a real decision point.** Whenever this playbook
reaches a point only a person can resolve (see "Decision points" below),
stop and offer concrete, mutually exclusive options rather than an
open-ended question — a structured multiple-choice prompt if your
environment has one (Claude Code's `AskUserQuestion` tool, for instance),
otherwise just spell the options out plainly in the message. Either way,
radio buttons, not essays.

## Step 0 — environment check and provider choice (once per session)

Before running `scripts/gate-issue.sh` or `scripts/review-issue.sh`, make
sure PyYAML is importable:

```bash
[ -d ../software-factory.venv ] || python3 -m venv ../software-factory.venv
source ../software-factory.venv/bin/activate
python3 -c "import yaml" 2>/dev/null || python3 -m pip install -r requirements.txt
```

Always create and activate the venv, then check PyYAML *inside* it — Step 5
below activates this same venv unconditionally, so if it were only created
on demand (skipped whenever the system `python3` happens to already have
PyYAML), that `source` would fail outright on a box where it was never
created, or silently run under a venv that itself lacks PyYAML because the
check never looked there. Also confirm
`gh auth status` succeeds — everything downstream assumes an authenticated
`gh`. There is no bot identity available for *writing*
(see `stations/run-factory-quirks.md` → "The identity wrinkle") — every station runs
as the single authenticated human account, whichever provider drives it.

**Pick a station provider and use it for every `--provider` flag below.**
This repo's stations are explicitly provider-agnostic
(`stations/README.md`: "Provider swappable") — `grok`, `opencode`, and
`claudecode` are all valid, and the choice can change per run. Detect what's
actually usable rather than assuming:

```bash
command -v grok > /dev/null 2>&1 && [[ -n "${XAI_API_KEY:-}" ]] && echo "grok: usable"
command -v claude > /dev/null 2>&1 && echo "claudecode: usable"
command -v opencode > /dev/null 2>&1 && echo "opencode: usable"
```

If more than one is usable, prefer **`grok`** for any run that includes a
**build** step (Step 3) — its builder is the one that actually runs
deterministically through `scripts/run-work-order.sh` (clone, run tests,
squash-commit, push, open the PR, set `factory:gate`, all in one script),
rather than an agent improvising file writes, git commits, and `gh pr
create` calls through its own tool use. The missing-work-order-paperwork gap
in `stations/run-factory-quirks.md` happened on `claudecode` runs precisely because
that path leaves "clone, commit, push, open PR" to the prompted agent
instead of to deterministic script logic — `grok`'s builder doesn't have
that failure mode. `grok` needs `XAI_API_KEY` set and the `grok` CLI on
`PATH`; if neither is available, fall back to `claudecode` or `opencode` and
expect to double-check the work-order paperwork a little more carefully
after Step 3. Tell the user which provider you picked and why, once, rather
than silently defaulting.

Every `--provider` flag shown below uses `"$PROVIDER"` — substitute
whichever was chosen.

## Step 1 — pick the ticket

If the user gave an issue number, use it directly. The issue lives in
`adamsuk/software-factory`, but it may name a different **target repo** via
a `Target repo: owner/repo` line in its triage comment or body — track both:
`issue_repo` (always `adamsuk/software-factory` unless told otherwise) and
`repo` (the target).

If no issue number was given, pick one, in this order, and say which rule
picked it:

1. `bash scripts/factory-flagged.sh` — anything flagged `priority: next` is
   explicitly queued by the user from the board; work the top one (it's
   already sorted P0→P3, then issue number). This script is read-only.
2. No flagged work → oldest open `factory:ready` issue:
   `gh issue list --repo adamsuk/software-factory --state open --label factory:ready --json number,title,labels,createdAt`,
   preferring one also labelled `quick win`.
3. Nothing `factory:ready` either → look at `factory:triage` issues that are
   **not** labelled `decision` and don't obviously need a protected-path
   change just to triage. Tell the user which one looks most promising and
   why, and offer to run intake on it — don't silently pick for them when
   the backlog is this cold, since "what to work on next" is itself useful
   information to surface, not just a mechanical default.

## Step 2 — intake (only if the issue is `factory:triage` or unlabelled)

```bash
scripts/station-run.sh --provider "$PROVIDER" --issue <N> --repo adamsuk/software-factory intake /dev/null
```

This posts the triage comment and sets `factory:ready` or `factory:blocked`
itself — don't relabel by hand. **If it lands on `factory:blocked`** (a
`decision` label, a protected path, the target not enrolled, etc.), stop and
ask the user (decision point: see below). Don't try to push a `decision`
issue forward yourself; intake is deliberately forbidden from doing that too.

## Step 3 — foreman pick / build (once `factory:ready`)

```bash
scripts/foreman-orchestrate.sh pick --provider "$PROVIDER"
```

This writes the work order to `agents/work-orders/<owner>_<repo>-<issue>.md`
in **this** repo, builds the target repo, and opens the pull request
(setting `factory:gate`). Report the PR link once it's up.

**Known gap, mainly on `claudecode`/`opencode`: the work-order paperwork
sometimes doesn't land** (see Step 0's provider note for why). Check for it
after the run regardless of provider — cheap to check, expensive to assume:

Check the **specific ref** the file would actually be read from later
(Step 5), not history in general — searching all refs risks finding a
same-named file on an unrelated or stale branch and wrongly concluding
there's nothing to reconstruct:

```bash
# Same-repo ticket: the file would be on the PR branch itself. Check the
# fetch itself, not just the cat-file — a failed fetch leaves whatever was
# already in origin/<branch> locally (possibly nothing, possibly stale),
# and silently proceeding on that is how this ends up checking the wrong
# content.
git fetch origin "<branch>" --quiet || { echo "fetch failed" >&2; exit 1; }
git cat-file -e "origin/<branch>:agents/work-orders/adamsuk_software-factory-<issue>.md" 2>/dev/null \
  && echo "found on <branch>" || echo "missing"

# Cross-repo ticket: check main (a chore PR may already be merged), and —
# if a chore PR is still open — check the file on *that* ref too, not just
# whether the PR exists. A chore PR can be open without the file yet (for
# example if only the PR itself landed but not its commit).
git fetch origin main --quiet || { echo "fetch failed" >&2; exit 1; }
git cat-file -e "origin/main:agents/work-orders/<owner>_<repo-name>-<issue>.md" 2>/dev/null \
  && echo "found on main" || echo "not on main"
chore_pr=$(gh pr list --repo adamsuk/software-factory --head "chore/<issue>-work-order" --state open --json number --jq '.[0].number // empty')
if [[ -n "$chore_pr" ]]; then
  git fetch origin "chore/<issue>-work-order" --quiet || { echo "fetch failed" >&2; exit 1; }
  git cat-file -e "origin/chore/<issue>-work-order:agents/work-orders/<owner>_<repo-name>-<issue>.md" 2>/dev/null \
    && echo "found on chore PR #$chore_pr" || echo "missing on chore PR #$chore_pr"
fi
```

(Match the exact expected filename, not a loose substring — issue `12`
would otherwise also match a file or commit for issue `112`.)

If it's missing, reconstruct it from the issue's triage comment + the PR's
own diff/title (same front-matter shape foreman.md documents — `repo`,
`issue`, `issue_repo`, `title`, `branch`, `base`, `test_command`,
`setup_command`, `changelog`, `merge_allowed`, `review_bot`, `attempt`,
`created`), then land it the way the ticket's shape calls for:

- **Cross-repo ticket** (target repo ≠ `adamsuk/software-factory`): open a
  dedicated `chore/<issue>-work-order` PR into `adamsuk/software-factory`
  (branch `chore/<issue>-work-order`, title
  `chore: work order for adamsuk/software-factory#<issue>`, label
  `skip-changelog`, body `Work order for #<issue> (<short description>). Built in <target-repo>#<pr-number>.` —
  matches existing examples like #248, #249, #277).
- **Same-repo ticket** (target repo == `adamsuk/software-factory`): commit
  the file directly onto the PR's own branch instead — it rides in with the
  real PR, no separate chore PR (see #275/#276 for the pattern). Use a
  throwaway worktree so you don't disturb the branch you're actually working
  in: `git worktree add /tmp/<tag> origin/<branch> --detach`, add the file,
  commit, `git push origin HEAD:<branch>`, then
  `git worktree remove /tmp/<tag>`.

## Step 4 — wait for checks, then handle merge conflicts if any

Poll in the background rather than blocking the conversation:

```bash
cat <<'SCRIPT' > /tmp/sf-poll-<N>.sh
#!/usr/bin/env bash
set -euo pipefail
for i in $(seq 1 60); do
  out=$(gh pr checks <PR> --repo <target-repo> --json state 2>/dev/null || echo '[]')
  count=$(printf '%s' "$out" | jq 'length')
  if [[ "$count" -gt 0 ]] && printf '%s' "$out" | jq -e '[.[] | select(.state=="PENDING" or .state=="QUEUED" or .state=="IN_PROGRESS")] | length == 0' >/dev/null 2>&1; then
    echo "settled"; exit 0
  fi
  sleep 20
done
echo "timed out waiting"
SCRIPT
bash /tmp/sf-poll-<N>.sh
```

Run that in the background rather than sitting in a foreground sleep loop
— however your environment supports backgrounding a shell command (Claude
Code's Bash tool takes `run_in_background: true` and notifies you when it
exits) — and pick the thread back up once it reports `settled`.

**CodeRabbit may show `skipping`** on a PR authored by `software-factory-line[bot]`
— that's a known open bug in this repo (#209), not a real block. Only the
repo's own `required_checks` (from `.github/factory.yml` — e.g. `ShellCheck`,
`changelog`, `tests` for software-factory itself) matter for gating.

**Checks settling green is necessary, not sufficient — a PR with 6 open
CodeRabbit findings can still show every check as `pass`.** Before calling
anything "ready" (to the user, or by moving on to Step 5), also read the
actual review state: `gh pr view <PR> --repo <repo> --json reviews` for a
`COMMENTED`/`CHANGES_REQUESTED` review, and
`gh api repos/<repo>/pulls/<PR>/comments --jq 'length'` for inline comment
count. A green check run says nothing about whether a reviewer left findings
— that's a separate signal, and skipping it is exactly the mistake this
playbook exists to prevent elsewhere in the pipeline, so don't make it here.

**If `mergeStateStatus` is `DIRTY` / `mergeable: CONFLICTING`**, find out
exactly what conflicts before deciding who should fix it.

**Work in the PR's own repo, not this one.** `<repo>` here is the ticket's
**target** repo (from Step 1) — for a cross-repo ticket that is *not*
`adamsuk/software-factory`, so the PR's branch lives there, not in this
checkout, and this checkout's `origin` must never stand in for it. Clone it
fresh rather than reusing anything local. Also validate the branch name
before it ever reaches a shell command — it's going to be interpolated, and
an untrusted-looking branch name (this repo's own threat model treats
anything that came off GitHub, including branch names, as untrusted input)
has no business being executed as anything other than a literal string:

```bash
branch="<branch>"   # e.g. factory/110-target-repo-field or chore/275-work-order
case "$branch" in
  factory/[0-9]*-*|chore/[0-9]*-*) ;;
  *) echo "unexpected branch shape: $branch" >&2; exit 1 ;;
esac

git clone --quiet "https://github.com/<repo>" /tmp/<tag>
cd /tmp/<tag>
git fetch --quiet origin "$branch"
git checkout --quiet "$branch"
git merge origin/main --no-commit --no-ff
git diff --name-only --diff-filter=U
```

(List every unmerged path, not just ones git happens to report as `UU` —
a conflict can also show as `AA`, `DD`, `AU`, `UA`, `DU`, or `UD` depending
on which side added/deleted/modified the file, and
`--diff-filter=U` catches all of those.)

**Don't clean up the clone yet** — if there's a conflict, the resolution
steps below still need it (edit the non-protected file, commit, push).
Only remove `/tmp/<tag>` once you're actually done with it: right away if
`git status` showed no conflict at all, or after the resolution has been
committed and pushed if it did.

Quote every expansion of `$branch` (and any other PR-derived value) in every
command you run, here and elsewhere in this playbook — never splice an
untrusted string straight into a shell line unquoted.

Protected paths are listed in `AGENTS.md` §5: existing test assertions, CI
config (`.github/workflows/**`, `.github/actions/**`, `.github/factory.yml`,
`.coderabbit.yaml`), lockfiles, and agent-instruction files (`AGENTS.md`,
`agents/**`, `CODEOWNERS` — note `agents/work-orders/**` is explicitly
**not** protected). A PR touching one of those files overall doesn't mean
the *conflict itself* does — check which file(s) the `--diff-filter=U`
output above actually lists.

- If the conflicting file(s) are **not** protected (very often just
  `CHANGELOG.md`, since two branches both add a dated entry near the top —
  resolve by keeping both bullets under the shared heading), resolve it
  directly: commit, then `git push origin HEAD:"$branch"` (quoted), clean up
  the clone.
- If resolving genuinely requires editing a protected file, stop and ask
  the user (decision point).

## Step 5 — gate

Fetch the work order locally if needed, then run the real gate script —
it's deterministic, not a judgment call, so run it directly rather than
through an agent.

**The work order always lives in `adamsuk/software-factory` (this repo),
never in the target repo** — even for a cross-repo ticket, where it rode in
on its own `chore/<issue>-work-order` PR rather than on `<branch>` (the
target repo's PR branch from Step 4). So the ref to read it from is a
*factory-repo* ref, not the PR branch:

- **Same-repo ticket**: the factory ref *is* `<branch>` — `origin` here
  already points at `adamsuk/software-factory`.
- **Cross-repo ticket**: the factory ref is `main` once the chore PR has
  merged, or `chore/<issue>-work-order` while it's still open — Step 3
  already checked both of those specific refs, so reuse that result rather
  than searching history again.

```bash
source ../software-factory.venv/bin/activate   # from step 0
git show "origin/<factory-ref>:agents/work-orders/<file>.md" > /tmp/<file>.md
scripts/gate-issue.sh /tmp/<file>.md
```

One word comes back:

| Result | Meaning | What to do |
| --- | --- | --- |
| `pending` | checks not all done | re-poll (step 4) |
| `review` | checks green, moved to `factory:review` | continue to step 6 |
| `retry` | a required check failed | if `attempt` is already 3, or the fix needs a protected path, stop and ask; otherwise this is a real fix-loop round — describe the failure and ask whether to attempt it or hand it off |
| `blocked` | already labelled + commented by the script | report it as-is, nothing more to do |
| `skip` | the issue isn't currently `factory:gate` | most often this means a fix was pushed after a `factory:building` swap and nothing moved the label back — run `scripts/station-post.sh pr --repo <repo> --issue <N> --head <branch> --title "<title>" --body-file <any-file>` (safe to run directly: it reuses the existing open PR and only swaps the label) and re-run gate |

## Step 6 — review

```bash
scripts/foreman-orchestrate.sh review --provider "$PROVIDER" --issue <N> --repo <target-repo> --pr <PR> --sha <head-sha>
```

This waits for the review bot, then posts an independent **PASS / FIX /
ESCALATE** verdict via `scripts/station-post.sh verdict` — it comments on
the PR and swaps the label on the issue itself (the station's own role
brief handles any cross-repo `--issue-repo` nuance; nothing extra to do
here).

- **ESCALATE** → always stop and surface the stated reason to the user
  (decision point). Never try to push past it.
- **FIX**, small and non-protected (a missing test-wiring line, a typo, a
  config field a linter flagged) → apply it directly: edit on the branch in
  a throwaway worktree, commit, push, reply to the specific review comment
  acknowledging the fix, resolve its thread
  (`gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "<id>"}) { thread { isResolved } } }'`
  — get `<id>` from the `reviewThreads` GraphQL query, matched by **`path`
  *and* `line`** — a file can carry several open threads, and matching on
  `path` alone risks resolving the wrong one and leaving the actual finding
  unresolved), then loop back to step 4. **FIX, substantive or protected-path** → stop
  and ask (decision point).
- **PASS** → this is the natural end of what this playbook does on its own.
  **Always** stop and ask before approving or merging (decision point) —
  this repo sets `agents.merge: false` everywhere, and approving/merging
  as an agent has been hard-blocked experimentally in at least one harness
  (Claude Code's auto-mode classifier) regardless of settings, which is
  reason enough to treat it as off-limits for automation here on
  principle, not harness-specific luck — see `stations/run-factory-quirks.md`.
  Never call `gh pr review --approve` or `gh pr merge` as a way to
  "finish the job."

## Step 7 — after a merge

Check how the PR referenced the issue:

- **`Closes #N`** (same-repo ticket) → the issue auto-closes on merge. It
  will likely still carry its last status label (`factory:blocked`,
  `factory:review`, ...) even though it's closed — that's a cosmetic
  mismatch 09 Return normally cleans up, not something to fix inline unless
  asked.
- **`Refs owner/repo#N`** (cross-repo ticket) → it does **not** auto-close.
  AGENTS.md §2 requires closing it by hand with a comment linking the merged
  PR. Ask the user whether to do that now (decision point) rather than just
  doing it, since it's a real GitHub write and easy to batch with other
  cleanup if they're mid-session on something else.

## Decision points — always ask, never guess

Offer concrete options at each of these — structured multiple-choice if
the environment supports it, plainly spelled out otherwise. A rough
template for each:

| Situation | Ask | Typical options |
| --- | --- | --- |
| Intake → `factory:blocked` | "Intake blocked #N: <reason from its comment>. How do you want to proceed?" | Answer the decision myself / Skip this ticket, pick another / Something else |
| Conflict needs a protected file edited | "Resolving the conflict on <branch> means editing <protected file>. That's a person's call per AGENTS.md §5." | I'll resolve it myself / Resolve it anyway, it's trivial / Skip for now |
| Gate `retry`, attempt < 3, non-protected | "<Check> failed on <PR>: <summary>. Want me to attempt a fix?" | Try a fix (one round) / I'll handle it / Stop here |
| Gate `retry`, attempt == 3 or protected | "<PR> has exhausted its fix-loop budget / needs a protected-path fix. Scott must act (AGENTS.md §4/§5)." | Acknowledge, I'll take it from here / Something else |
| Review FIX, substantive/protected | "<PR> needs a fix that <reason it's not safe to auto-apply>." | I'll apply it myself / Hand it to a builder run / Skip for now |
| Review ESCALATE | "Reviewer escalated <PR>: <stated reason>." | Tell me more / I'll look at it myself / Something else |
| Review PASS | "<PR> passed review, all checks green. Ready to merge, but that's your call (agents.merge: false)." | Approve & merge it yourself now / I'll handle it later / Reopen as the bot first (see below) |
| PASS, but PR author == your own `gh` login | same as above, plus the self-approval wrinkle | Reopen as the bot so I can approve it myself / Approve with a different account / Leave it for later |
| Cross-repo merge, issue needs closing | "<PR> merged. #N (cross-repo, `Refs`) needs closing by hand per AGENTS.md §2." | Close it now with a link / I'll do it myself / Leave it open for now |

For the full detail behind the identity wrinkle (self-approval, and the
"reopen as the bot" recipe that actually works), the CodeRabbit-skip bug,
and the exact protected-paths list with citations, see
`stations/run-factory-quirks.md` — read it before the first time you hit
one of those situations in a run, since the recipes there are easy to get
subtly wrong (wrong flag, wrong identity, wrong GraphQL id) on the first
try.
