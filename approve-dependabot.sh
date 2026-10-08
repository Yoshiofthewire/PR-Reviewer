#!/usr/bin/env bash
# Usage: DRY_RUN=1 ./approve-dependabot.sh [owner/repo]
# With no argument, use the repository in the current directory.
set -uo pipefail

if [[ $# -gt 1 || ${1:-} == -* ]]; then
  echo 'Usage: DRY_RUN=1 ./approve-dependabot.sh [owner/repo]' >&2
  exit 1
fi

repo_args=()
[[ $# -eq 0 ]] || repo_args+=("$1")
repo=$(gh repo view "${repo_args[@]}" --json nameWithOwner,isArchived \
  --jq 'select(.isArchived == false) | .nameWithOwner') || exit 1
if [[ -z $repo ]]; then
  echo 'Skipping archived repository.' >&2
  exit 0
fi

# Paginate rather than silently omitting PRs after the first page.
numbers=$(gh api "repos/$repo/pulls?state=open&per_page=100" --paginate \
  --jq '.[] | select(.user.login == "dependabot[bot]" and .draft == false) | .number') || exit 1

status=0
while IFS= read -r number; do
  [[ -n $number ]] || continue
  if [[ ${DRY_RUN:-0} == 1 ]]; then
    printf 'Would approve %s#%s\n' "$repo" "$number"
    continue
  fi
  if gh pr review "$number" --repo "$repo" --approve \
    --body 'Automated Dependabot approval on behalf of Yoshi. Script authored by gpt-6.1-sol using ponytail on behalf of Yoshi.'; then
    printf 'Approved %s#%s\n' "$repo" "$number"
  else
    printf 'Failed to approve %s#%s\n' "$repo" "$number" >&2
    status=1
  fi
done <<<"$numbers"
exit "$status"
