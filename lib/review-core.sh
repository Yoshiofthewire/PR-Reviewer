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

# Security only. simplicity/ponytail-review and hostile/hostile-review were
# dropped: they never cleared, so the gate was never passable.
PERSONA_ORDER=(security)
declare -A PERSONA_SKILL=([security]=security-audit)
declare -A PERSONA_TITLE=([security]="Security review")

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

# Fails closed: anything that isn't unambiguously private (isPrivate:true) is
# treated as public. Over-redacting a private repo is a cosmetic annoyance;
# under-redacting a public one is a disclosure, so ambiguity must resolve to 1.
visibility_flag() { # visibility_flag <gh repo view --json isPrivate output>
  local out
  out=$(jq -r 'if .isPrivate == true then 0 else 1 end' <<<"$1" 2>/dev/null)
  [[ $out == 0 || $out == 1 ]] && printf '%s' "$out" || printf '1'
}

# Publishing an exploitable finding against an unfixed public branch is
# uncoordinated disclosure, so public security reports name severity and file only.
# <report-reference> must be where the caller actually delivered the full finding
# -- a hand-off board URL or a local path -- or empty if every route failed; this
# function performs no I/O itself and never checks that the reference resolves.
redact_findings() { # redact_findings <persona> <is-public 0|1> <body> [report-reference]
  local persona="$1" public="$2" body="$3" ref="${4:-}" line sev="P?" file
  local withheld='Detail withheld: this repository is public, and posting an unfixed finding here would be public disclosure.'
  if [[ $persona != security || $public != 1 ]]; then
    printf '%s' "$body"
    return 0
  fi
  case $ref in
    http://*|https://*)
      printf '%s The full report was posted to the hand-off board at %s, where it is readable by the operator and expires seven days after the last post.\n' \
        "$withheld" "$ref"
      ;;
    ?*)
      printf '%s The full report was written to `%s`.\n' "$withheld" "$ref"
      ;;
    *)
      printf '%s The full report could not be delivered anywhere; check the operator logs.\n' "$withheld"
      ;;
  esac
  while IFS= read -r line; do
    if [[ $line =~ ^\#\#\#[[:space:]]\[(P[0-9])\] ]]; then
      sev="${BASH_REMATCH[1]}"
    elif [[ $line =~ ^-[[:space:]]Location:[[:space:]]\`([^:\`]+) ]]; then
      file="${BASH_REMATCH[1]}"
      printf '\n- %s in `%s`' "$sev" "$file"
    fi
  done <<<"$body"
  printf '\n'
}

# Board slugs are lowercase letters, digits and hyphens, must start with a
# letter or digit, and are capped at 64 characters. One folder per pull request:
# a re-review appends a post to the same folder rather than opening a new one.
handoff_slug() { # handoff_slug <repo> <number>
  local slug
  slug=$(printf 'pr-reviewer-%s-%s' "$1" "$2" |
    tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//')
  slug=${slug:0:64}
  while [[ $slug == *- ]]; do slug=${slug%-}; done
  printf '%s' "$slug"
}

# The board post carries what the public comment cannot: the finding in full.
# It names the pull request and head sha because the reader arrives from the
# board, with no idea which review this is.
handoff_post_body() { # handoff_post_body <repo> <number> <head> <model> <verdict> <body>
  local repo="$1" number="$2" head="$3" model="$4" verdict="$5" body="$6" status
  status="changes required"
  [[ $verdict == cleared ]] && status="cleared"
  printf '## %s#%s - security review %s\n\n- Pull request: https://github.com/%s/pull/%s\n- Head: `%s`\n\nThe pull request is public, so its comment names severity and file only. The finding in full:\n\n%s\n\n---\n%s\n' \
    "$repo" "$number" "$status" "$repo" "$number" "$head" "$body" \
    "$(signature "$model" "${PERSONA_SKILL[security]}")"
}

# Why repo_allowed rejected a repo. Logging only; never gates behaviour.
repo_filter_reason() { # repo_filter_reason <repo>
  local repo="$1" deny="${EXCLUDE_REPOSITORIES:-}"
  deny="${deny// /}"
  case ",$deny," in
    *",$repo,"*) printf 'excluded by EXCLUDE_REPOSITORIES'; return 0 ;;
  esac
  printf 'not in REPOSITORIES allowlist'
}
