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
