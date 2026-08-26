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

PERSONA_ORDER=(security simplicity hostile)
declare -A PERSONA_SKILL=(
  [security]=security-audit
  [simplicity]=ponytail-review
  [hostile]=hostile-review
)
declare -A PERSONA_TITLE=(
  [security]="Security review"
  [simplicity]="Simplicity review"
  [hostile]="Hostile review"
)

signature() { # signature <model> <skill>
  printf '*%s using %s on behalf of Yoshi*' "$1" "$2"
}

render_comment() { # render_comment <persona> <model> <head> <seen> <verdict> <body>
  local persona="$1" model="$2" head="$3" seen="$4" verdict="$5" body="$6" status
  status="changes required"
  [[ $verdict == cleared ]] && status="cleared"
  printf '%s\n## %s - %s\n\n%s\n\n---\n%s\n' \
    "$(state_emit "$persona" "$head" "$seen" "$verdict")" \
    "${PERSONA_TITLE[$persona]}" "$status" "$body" \
    "$(signature "$model" "${PERSONA_SKILL[$persona]}")"
}

render_summary() { # render_summary <head> <seen> <cleared-count> <status-lines>
  local head="$1" seen="$2" cleared="$3" lines="$4" verdict=open
  [[ $cleared -eq ${#PERSONA_ORDER[@]} ]] && verdict=cleared
  printf '%s\n## Autonomous review - %s/%s personas cleared\n\n%s\n\n_Merging remains a human decision; this bot never approves._\n' \
    "$(state_emit summary "$head" "$seen" "$verdict")" \
    "$cleared" "${#PERSONA_ORDER[@]}" "$lines"
}
