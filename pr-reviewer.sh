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
  local owners=() owner args=() kept=0 owners_raw repo number updated title
  owners_raw=$(resolve_owners) || return 1
  mapfile -t owners <<<"$owners_raw"
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

WORK_DIR="${WORK_DIR:-${XDG_RUNTIME_DIR:-/tmp}/pr-reviewer}"

# Files the CLI would auto-load as instructions. Renamed, not deleted: their real
# content still needs reviewing, and it stays visible both here and in the diff.
QUARANTINE_PATHS=(CLAUDE.md AGENTS.md .claude .cursor)

quarantine_instructions() { # quarantine_instructions <dir>
  local dir="$1" name
  for name in "${QUARANTINE_PATHS[@]}"; do
    [[ -e "$dir/$name" ]] || continue
    rm -rf "$dir/$name.quarantined"
    mv "$dir/$name" "$dir/$name.quarantined" || return 1
  done
  return 0
}

# Leftovers from a run that was killed before its trap fired.
reap_stale_checkouts() {
  [[ -d $WORK_DIR ]] || return 0
  rm -rf "${WORK_DIR:?}"/* 2>/dev/null
  return 0
}

# refs/pull/<n>/head resolves for fork PRs too, which a branch name would not.
prepare_checkout() { # prepare_checkout <repo> <number> <dir>
  local repo="$1" number="$2" dir="$3"
  mkdir -p "$dir" || return 1
  git -C "$dir" init -q || return 1
  git -C "$dir" remote add origin "https://github.com/$repo" || return 1
  git -C "$dir" -c protocol.version=2 fetch -q --depth=1 origin \
    "refs/pull/$number/head" || return 1
  git -C "$dir" checkout -q FETCH_HEAD || return 1
  quarantine_instructions "$dir" || return 1
  return 0
}

main() {
  echo "not yet implemented" >&2
  return 1
}

if [[ ${BASH_SOURCE[0]:-} == "$0" ]]; then
  main "$@"
fi
