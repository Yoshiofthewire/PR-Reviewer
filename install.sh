#!/usr/bin/env bash
# Install the user timer. Idempotent: safe to re-run after editing the units.
set -uo pipefail
cd "$(dirname "$0")" || exit 1

units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p "$units" "${XDG_STATE_HOME:-$HOME/.local/state}" || exit 1
install -m644 systemd/pr-reviewer.service systemd/pr-reviewer.timer "$units/" || exit 1
systemctl --user daemon-reload || exit 1
systemctl --user enable --now pr-reviewer.timer || exit 1
systemctl --user list-timers pr-reviewer.timer --no-pager
