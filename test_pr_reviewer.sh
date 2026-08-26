#!/usr/bin/env bash
# Dependency-free checks for review logic. No network, no writes outside TMPDIR.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
# shellcheck source=lib/review-core.sh
source ./lib/review-core.sh

fails=0
fail() { echo "FAIL: $1" >&2; fails=$((fails + 1)); }

eq() { # eq <desc> <want> <got>
  [[ "$2" == "$3" ]] || fail "$1 (want '$2', got '$3')"
}

rc() { # rc <desc> <want-rc> <command...>
  local desc="$1" want="$2"
  shift 2
  "$@"
  local got=$?
  [[ $got -eq $want ]] || fail "$desc (want rc $want, got rc $got)"
}

contains() { # contains <desc> <haystack> <needle>
  case "$2" in *"$3"*) return 0 ;; esac
  fail "$1 (missing '$3')"
}

lacks() { # lacks <desc> <haystack> <needle>
  case "$2" in *"$3"*) fail "$1 (unexpectedly contains '$3')" ;; esac
  return 0
}

# --- repo_allowed ---
REPOSITORIES="" EXCLUDE_REPOSITORIES=""
rc "no lists allows everything" 0 repo_allowed me/kept

REPOSITORIES="me/kept, other/repo" EXCLUDE_REPOSITORIES=""
rc "allowlist admits listed repo" 0 repo_allowed me/kept
rc "allowlist rejects unlisted repo" 1 repo_allowed me/dropped

REPOSITORIES="me/kept" EXCLUDE_REPOSITORIES="me/kept"
rc "denylist beats allowlist" 1 repo_allowed me/kept

REPOSITORIES="" EXCLUDE_REPOSITORIES="me/kept-more"
rc "denylist does not match on prefix" 0 repo_allowed me/kept

# --- state block codec ---
BLOCK=$(state_emit security abc123 2026-08-26T09:00:00Z open)
eq "state_emit renders the documented format" \
  '<!-- pr-reviewer persona=security head=abc123 seen=2026-08-26T09:00:00Z verdict=open -->' \
  "$BLOCK"

eq "round-trip persona" security "$(state_field "$BLOCK" persona)"
eq "round-trip head" abc123 "$(state_field "$BLOCK" head)"
eq "round-trip seen" 2026-08-26T09:00:00Z "$(state_field "$BLOCK" seen)"
eq "round-trip verdict" open "$(state_field "$BLOCK" verdict)"

BODY="$BLOCK"$'\n''## Security review - changes required'$'\n''### [P0] Thing'
eq "field survives a full comment body" abc123 "$(state_field "$BODY" head)"

eq "absent block yields empty" "" "$(state_field "just prose" head)"
eq "absent field yields empty" "" "$(state_field "$BLOCK" nosuchfield)"
eq "malformed block yields empty" "" "$(state_field '<!-- pr-reviewer -->' head)"

# A comment quoting a state block in prose must not shadow the real one.
FIRST=$(state_emit hostile aaa 2026-01-01T00:00:00Z cleared)
eq "first block wins" aaa "$(state_field "$FIRST"$'\n'"$BLOCK" head)"

[[ $fails -eq 0 ]] || { echo "$fails check(s) failed" >&2; exit 1; }
echo "all checks passed"
