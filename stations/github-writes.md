# GitHub writes

When a station is started by `scripts/station-run.sh`, this file is part of the prompt. It applies to every provider, including OpenCode. The Grok watcher has its own poster and does not come through here.

The factory is readable on the issue only when each step leaves one comment and exactly one `factory:*` label. Say what changed, which pull request is live, and who must act. Do not leave that in the transcript.

## Rules

- Run `scripts/station-post.sh` for every factory comment, label move, and pull request. Do not call `gh issue comment`, `gh pr comment`, `gh pr create`, `gh issue edit`, or `gh pr merge` yourself.
- One issue, one branch `factory/<issue>-<slug>`, one open pull request. A second triage comment, a second open pull request, or a branch that is not `factory/<issue>-<slug>` is a failed run. `temp-branch` is not a factory branch.
- Never merge. `station-post.sh` will not merge. Merging stays in AGENTS.md §6.
- Do not post the same station comment again. If the script says it is already posted, stop.

## Commands

Triage, once. `--status ready` or `--status blocked`. The body is the normalised brief. The script adds `<!-- factory:triage -->` when the file does not start with it, then sets `factory:ready` or `factory:blocked`.

The script records the status on the comment's second line. A retry repairs a missing label only when every existing triage comment records the requested status; a different or unrecorded status is refused.

```bash
scripts/station-post.sh triage --repo owner/repo --issue N \
  --status ready --body-file /tmp/triage.md
```

Pickup, once, and only from `factory:ready`. Sets `factory:building` and comments the branch.

```bash
scripts/station-post.sh pickup --repo owner/repo --issue N \
  --branch factory/N-slug
```

Open or reuse the one pull request. Refuses any other open pull request for this issue. From `factory:building`, sets `factory:gate` and comments the pull request number.

```bash
scripts/station-post.sh pr --repo owner/repo --issue N \
  --head factory/N-slug --title "feat: short title (#N)" \
  --body-file /tmp/pr-body.md
```

The pull request body still starts with `Closes #N` when the issue is in that repo, then the five bench lines when a run has them: `attempt`, `test_command`, `tests`, `api_equiv_usd`, `num_turns`.

Verdict, on the pull request head. `--verdict` is `PASS`, `FIX`, or `ESCALATE`. `--protected yes` when the diff touches an AGENTS.md §5 path, as decided by piping the PR's changed paths (the diff from its merge base to its head in the target repository — not a working-tree diff, which misses commits already on the branch) through `scripts/protected-paths.sh` (work orders under `agents/work-orders/` do not count). `PASS` on an ordinary diff sets `factory:merge` and does not merge. `PASS` on a protected diff, and `ESCALATE`, set `factory:blocked` and say that the maintainer must act. `FIX` sets `factory:building`. For `FIX` and `ESCALATE`, pass the real number of should-fix findings with `--should-fix N`; without it the script records 1 for `FIX` and 0 for everything else.

```bash
scripts/station-post.sh verdict --repo owner/repo --pr N --issue N \
  --sha ABCDEF1 --verdict FIX --protected no --should-fix 2 \
  --summary "One or two sentences."
```

Stop before a pull request exists. Sets `factory:blocked` and comments why and who must act.

```bash
scripts/station-post.sh blocked --repo owner/repo --issue N \
  --body-file /tmp/why.md
```
