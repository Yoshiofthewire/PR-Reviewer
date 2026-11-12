#!/usr/bin/env bash
# Run a reviewer every TICK_SECONDS; the container's replacement for the systemd timer.
# A failed tick is logged and retried next time, never fatal.
set -uo pipefail
[[ $# -gt 0 ]] || { echo "usage: tick-loop.sh <command...>" >&2; exit 1; }
trap 'exit 0' TERM INT
while :; do
  "$@" || echo "tick-loop · $1 exited $?" >&2
  sleep "${TICK_SECONDS:-120}" &
  wait $!
done
