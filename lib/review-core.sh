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
