#!/usr/bin/env bash
# Install the five-minute tick: a systemd user timer on Linux, a launchd user
# agent on macOS. Idempotent: safe to re-run after editing the units.
set -uo pipefail
cd "$(dirname "$0")" || exit 1

DIR=$(pwd)
LABEL=com.urlxl.pr-reviewer

install_systemd() {
  units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  mkdir -p "$units" "${XDG_STATE_HOME:-$HOME/.local/state}" || return 1
  install -m644 systemd/pr-reviewer.service systemd/pr-reviewer.timer "$units/" || return 1
  systemctl --user daemon-reload || return 1
  systemctl --user enable --now pr-reviewer.timer || return 1
  systemctl --user list-timers pr-reviewer.timer --no-pager
}

install_launchd() {
  local agents plist bash_bin log
  agents="$HOME/Library/LaunchAgents"
  plist="$agents/$LABEL.plist"
  log="$HOME/Library/Logs/pr-reviewer.log"

  # The tick needs bash 4+ for mapfile and associative arrays; macOS ships 3.2.
  bash_bin=$(command -v bash)
  if [[ $("$bash_bin" -c 'echo ${BASH_VERSINFO[0]}') -lt 4 ]]; then
    bash_bin=""
    for candidate in /opt/homebrew/bin/bash /usr/local/bin/bash; do
      [[ -x $candidate ]] && { bash_bin="$candidate"; break; }
    done
  fi
  [[ -n $bash_bin ]] ||
    { echo "ERROR: bash 4+ not found; run 'brew install bash'" >&2; return 1; }
  command -v flock >/dev/null ||
    { echo "ERROR: flock not found; run 'brew install flock'" >&2; return 1; }

  # launchd starts with a bare PATH, so gh, jq, git, claude and flock are all
  # pinned here by the directories they were actually resolved from.
  local agent_path="/usr/bin:/bin:/usr/sbin:/sbin"
  local tool dir
  for tool in gh jq git claude flock; do
    dir=$(dirname "$(command -v "$tool")") || return 1
    case ":$agent_path:" in *":$dir:"*) ;; *) agent_path="$dir:$agent_path" ;; esac
  done

  mkdir -p "$agents" "$HOME/Library/Logs" "${XDG_STATE_HOME:-$HOME/.local/state}" || return 1
  sed -e "s|@BASH@|$bash_bin|g" \
      -e "s|@SCRIPT@|$DIR/pr-reviewer.sh|g" \
      -e "s|@DIR@|$DIR|g" \
      -e "s|@PATH@|$agent_path|g" \
      -e "s|@LOG@|$log|g" \
      "launchd/$LABEL.plist.in" >"$plist" || return 1
  chmod 644 "$plist" || return 1
  plutil -lint "$plist" >/dev/null || return 1

  launchctl bootout "gui/$UID/$LABEL" 2>/dev/null
  launchctl bootstrap "gui/$UID" "$plist" || return 1
  launchctl print "gui/$UID/$LABEL" | grep -E '^\s+(state|path) ='
  echo "installed $LABEL; logs at $log"
}

case "$(uname -s)" in
  Darwin) install_launchd || exit 1 ;;
  Linux)  install_systemd || exit 1 ;;
  *) echo "ERROR: no scheduler for $(uname -s); run pr-reviewer.sh from cron" >&2; exit 1 ;;
esac
