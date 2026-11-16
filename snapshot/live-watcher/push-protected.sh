#!/usr/bin/env bash
# push-protected.sh ISSUE_REPO NUM : after run-work-order exit 4 (protected paths) on an issue
# Scott approved, push the newest build clone's branch and open a PR for Scott to merge.
set -u
repo=$1; n=$2; slug=${repo/\//_}
cd /workspace/factory-watch
# Approval: adamsuk comment containing "Scott (via chat", OR bot comment containing
# "Scott (via chat" or "Scott approved protected-path" (chat approval recorded as bot).
# GraphQL author.login for the app is "software-factory-line" (no [bot] suffix).
ok=$(gh issue view "$n" -R "$repo" --json comments --jq '
  [.comments[]
   | select(
       (.author.login=="adamsuk" and (.body|test("Scott \\(via chat")))
       or
       ((.author.login=="software-factory-line" or .author.login=="software-factory-line[bot]")
         and (.body|test("Scott \\(via chat|Scott approved protected-path")))
     )
  ] | length')
[[ ${ok:-0} -gt 0 ]] || { echo "no Scott approval on $repo#$n"; exit 2; }
order=orders/${slug}-${n}.md
target=$(grep -m1 -E '^(target_)?repo:' "$order" | awk '{print $2}'); target=${target:-$repo}
d=$(ls -dt /workspace/wo-${target/\//_}-${n}-* 2>/dev/null | grep -v '\.[a-z]*$' | head -1)
[[ -d $d/.git ]] || { echo "no clone for $repo#$n"; exit 3; }
cd "$d"; br=$(git branch --show-current)
[[ $br == factory/* ]] || { echo "bad branch $br"; exit 3; }
[[ $(git rev-list --count origin/main..HEAD) -ge 1 ]] || { echo "no commits"; exit 3; }
merged=$(gh pr list -R "$target" --head "$br" --state merged --json number --jq length)
[[ ${merged:-0} -eq 0 ]] || { echo "already merged"; exit 3; }
git push -q -u origin "$br" 2>&1 | grep -v '^remote:' || true
title=$(git log -1 --format=%s)
files=$(git diff --name-only origin/main...HEAD | sed 's/^/- `/; s/$/`/')
body="Closes ${repo}#${n}

Built by Grok Build. This change touches protected paths, so Scott reviews and merges it himself (he approved builders opening PRs for protected MVP station tickets on 26 Oct).

Files:
${files}"
[[ $target == "$repo" ]] && body=${body/Closes ${repo}#${n}/Closes #${n}}
url=$(gh pr list -R "$target" --head "$br" --json url --jq '.[0].url')
[[ -n $url ]] || url=$(gh pr create -R "$target" --head "$br" --title "$title" --body "$body")
gh pr comment "$url" --body "@coderabbitai review" >/dev/null
gh issue edit "$n" -R "$repo" --remove-label factory:blocked --remove-label factory:building --add-label factory:review >/dev/null
echo "$url"
