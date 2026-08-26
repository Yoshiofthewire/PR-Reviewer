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

[[ $fails -eq 0 ]] || { echo "$fails check(s) failed" >&2; exit 1; }
echo "all checks passed"
