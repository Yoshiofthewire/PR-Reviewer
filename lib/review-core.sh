#!/usr/bin/env bash
# Pure review logic. No network, no filesystem writes, no side effects.
# Sourced by pr-reviewer.sh and by test_pr_reviewer.sh.

# Comma-separated allowlist/denylist membership, spaces tolerated.
repo_allowed() { # repo_allowed <repo>
  local repo="$1" allow="${REPOSITORIES:-}" deny="${EXCLUDE_REPOSITORIES:-}"
  allow="${allow// /}"
  deny="${deny// /}"
  case ",$deny," in *",$repo,"*) return 1 ;; esac
  [[ -z $allow ]] && return 0
  case ",$allow," in *",$repo,"*) return 0 ;; esac
  return 1
}

state_emit() { # state_emit <persona> <head> <seen> <verdict>
  printf '<!-- pr-reviewer persona=%s head=%s seen=%s verdict=%s -->' "$1" "$2" "$3" "$4"
}

state_field() { # state_field <comment-body> <field>
  local body="$1" field="$2" block re
  block=$(grep -o -m1 '<!-- pr-reviewer [^>]*-->' <<<"$body")
  [[ -n $block ]] || return 0
  re="[[:space:]]$field=([^[:space:]]+)"
  [[ $block =~ $re ]] && printf '%s' "${BASH_REMATCH[1]}"
  return 0
}

# ISO 8601 UTC timestamps compare correctly as strings.
needs_review() { # needs_review <state-head> <state-seen> <current-head> <newest-reply>
  local state_head="$1" state_seen="$2" cur_head="$3" newest="$4"
  [[ -z $state_head ]] && return 0
  [[ $state_head != "$cur_head" ]] && return 0
  [[ -z $newest ]] && return 1
  [[ -z $state_seen ]] && return 0
  [[ $newest > $state_seen ]] && return 0
  return 1
}
