#!/usr/bin/env bash
# push-protected.sh ISSUE_REPO NUM : after run-work-order exit 4 (protected paths) on an issue
# the maintainer approved, push the newest build clone's branch and open a PR for the maintainer to merge.
# Approval is a comment by FACTORY_APPROVER_LOGIN that contains <!-- factory:approve -->,
# or the legacy "<Name> (via chat" marker, kept for compatibility.
set -u
repo=$1; n=$2; slug=${repo/\//_}
# >>> factory env: the shared settings live in factory-env.sh, beside this script.
factory_env_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/factory-env.sh"
if [[ ! -r $factory_env_file ]]; then
  printf '%s: cannot read %s (factory-env.sh must sit beside the watcher scripts)\n' "${BASH_SOURCE[0]##*/}" "$factory_env_file" >&2
  exit 1
fi
# shellcheck source=scripts/watcher/factory-env.sh
source "$factory_env_file"
# <<< factory env
factory_resolve_repos || true
[[ -n $FACTORY_APPROVER_LOGIN ]] || { echo "no approver: set FACTORY_APPROVER_LOGIN or FACTORY_HOME_REPO"; exit 2; }
# shellcheck disable=SC2164 # || exit would add a failure branch
cd "$FACTORY_WATCH_ROOT"
ok=$(gh issue view "$n" -R "$repo" --json comments --jq '[.comments[]|select(.author.login==env.FACTORY_APPROVER_LOGIN)|.body|select(test("<!-- factory:approve -->") or test("\\b[A-Z][a-z]+ \\(via chat"))]|length')
[[ ${ok:-0} -gt 0 ]] || { echo "no maintainer approval on $repo#$n"; exit 2; }
order=orders/${slug}-${n}.md
target=$(grep -m1 -E '^(target_)?repo:' "$order" | awk '{print $2}'); target=${target:-$repo}
# shellcheck disable=SC2010 # ls -dt | grep keeps newest-first; a glob loop would change the command
d=$(ls -dt "${FACTORY_CLONE_ROOT}/wo-${target/\//_}-${n}-"* 2>/dev/null | grep -v '\.[a-z]*$' | head -1)
[[ -d $d/.git ]] || { echo "no clone for $repo#$n"; exit 3; }
# shellcheck disable=SC2164 # || exit would add a failure branch
cd "$d"; br=$(git branch --show-current)
[[ $br == factory/* ]] || { echo "bad branch $br"; exit 3; }
[[ $(git rev-list --count origin/main..HEAD) -ge 1 ]] || { echo "no commits"; exit 3; }
merged=$(gh pr list -R "$target" --head "$br" --state merged --json number --jq length)
[[ ${merged:-0} -eq 0 ]] || { echo "already merged"; exit 3; }
git push -q -u origin "$br" 2>&1 | grep -v '^remote:' || true
title=$(git log -1 --format=%s)
files=$(git diff --name-only origin/main...HEAD | sed "s/^/- \`/; s/\$/\`/")
body="Closes ${repo}#${n}

Built by Grok Build. This change touches protected paths, so the maintainer reviews and merges it (they approved builders opening PRs for protected MVP station tickets on 26 Oct).

Files:
${files}"
[[ $target == "$repo" ]] && body=${body/Closes ${repo}#${n}/Closes #${n}}
url=$(gh pr list -R "$target" --head "$br" --json url --jq '.[0].url')
[[ -n $url ]] || url=$(gh pr create -R "$target" --head "$br" --title "$title" --body "$body")
gh pr comment "$url" --body "@coderabbitai review" >/dev/null
gh issue edit "$n" -R "$repo" --remove-label factory:blocked --remove-label factory:building --add-label factory:review >/dev/null
echo "$url"
