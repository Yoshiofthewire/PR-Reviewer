#!/usr/bin/env bash
# Review open pull requests locally through three persona reviewers.
set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/review-core.sh
source "$SCRIPT_DIR/lib/review-core.sh"

MAX_PRS_PER_TICK="${MAX_PRS_PER_TICK:-5}"
MAX_DIFF_BYTES="${MAX_DIFF_BYTES:-180000}"
CLAUDE_MODEL="${CLAUDE_MODEL:-opus}"
REASONING_EFFORT="${REASONING_EFFORT:-high}"

resolve_owners() {
  gh api user --jq .login || return 1
  gh api user/orgs --jq '.[].login' || return 1
}

discover_prs() {
  local owners=() owner args=() kept=0 line repo number updated title
  mapfile -t owners < <(resolve_owners) || return 1
  for owner in "${owners[@]}"; do
    [[ -n $owner ]] && args+=(--owner "$owner")
  done
  [[ ${#args[@]} -gt 0 ]] || return 1

  while IFS=$'\t' read -r repo number updated title; do
    [[ -n $repo ]] || continue
    repo_allowed "$repo" || continue
    if [[ $kept -ge $MAX_PRS_PER_TICK ]]; then
      echo "cap reached, deferring $repo#$number to a later tick" >&2
      continue
    fi
    kept=$((kept + 1))
    printf '%s\t%s\t%s\t%s\n' "$repo" "$number" "$updated" "$title"
  done < <(
    gh search prs --state=open --archived=false "${args[@]}" \
      --limit 100 --json repository,number,updatedAt,title,isDraft |
      jq -r 'map(select(.isDraft | not))
             | sort_by(.updatedAt) | reverse
             | .[] | [.repository.nameWithOwner, .number, .updatedAt, .title]
             | @tsv'
  )
}

main() {
  echo "not yet implemented" >&2
  return 1
}

if [[ ${BASH_SOURCE[0]:-} == "$0" ]]; then
  main "$@"
fi
