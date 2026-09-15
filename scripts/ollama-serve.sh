#!/usr/bin/env bash
# =============================================================
# ollama-serve.sh — on-demand Ollama daemon control (lm start / lm stop)
# =============================================================
# Rationale: on laptops, keeping the daemon resident (LaunchAgent with
# RunAtLoad+KeepAlive) wastes battery when local models are unused.
# This script gives manual control:
#
#   lm start            # start daemon now (launchd kickstart; nohup fallback)
#   lm stop             # stop daemon (stays down once autostart is off)
#   lm autostart off    # login no longer starts Ollama (RunAtLoad/KeepAlive=false)
#   lm autostart on     # restore login auto-start
#   lm autostart status # show current autostart + daemon state
#
# Note: `lm deploy` / `lm upgrade-ollama` start the daemon on demand anyway.
# With KeepAlive=false a crashed daemon stays down — re-run `lm start`.
# =============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"

LABEL="homebrew.mxcl.ollama"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
GUI="gui/$(id -u)"
API="http://127.0.0.1:11434"
LOG_DIR="/opt/homebrew/var/log"

api_up() { curl -s -m 2 -o /dev/null "$API/api/tags"; }

plist_bool() {  # plist_bool <Key> -> true|false|"" (missing)
  /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || true
}

wait_up() {
  local i
  for i in $(seq 1 20); do
    api_up && return 0
    sleep 1
  done
  return 1
}

wait_down() {
  local i
  for i in $(seq 1 10); do
    api_up || return 0
    sleep 1
  done
  return 1
}

cmd_start() {
  if api_up; then
    ok "daemon already running (127.0.0.1:11434)"
    return 0
  fi
  # Preferred: launchd service (carries EnvironmentVariables from the plist)
  if [[ -f "$PLIST" ]]; then
    launchctl bootstrap "$GUI" "$PLIST" 2>/dev/null || true
    launchctl kickstart "$GUI/$LABEL" 2>/dev/null || true
    # kickstart returns before the port is bound — give launchd a grace window
    local i
    for i in 1 2 3 4 5; do
      api_up && break
      sleep 1
    done
  fi
  if ! api_up; then
    # Fallback: plain background process with the same env as the plist
    local bin
    bin="$(command -v ollama || true)"
    [[ -n "$bin" ]] || { err "ollama not installed — run: lm upgrade-ollama"; exit 1; }
    warn "launchd service unavailable — starting via nohup"
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 \
      nohup "$bin" serve >>"$LOG_DIR/ollama.log" 2>&1 &
  fi
  if wait_up; then
    ok "daemon online (127.0.0.1:11434)"
  else
    err "daemon did not come up in 20s — check $LOG_DIR/ollama.log"
    exit 1
  fi
}

cmd_stop() {
  if ! api_up && ! pgrep -f '[o]llama serve' >/dev/null 2>&1; then
    ok "daemon not running"
    return 0
  fi
  if [[ "$(plist_bool KeepAlive)" == "true" ]]; then
    warn "KeepAlive=true — launchd would restart it; switching to manual mode first (lm autostart off)"
    cmd_autostart_off
  fi
  launchctl kill SIGTERM "$GUI/$LABEL" 2>/dev/null || true
  pkill -f '[o]llama serve' 2>/dev/null || true
  if wait_down; then
    ok "daemon stopped"
  else
    err "daemon still answering after 10s — check: pgrep -fl ollama"
    exit 1
  fi
}

_reload_service() {  # reload plist into launchd; with RunAtLoad=false it stays down
  launchctl bootout "$GUI/$LABEL" 2>/dev/null || true
  launchctl bootstrap "$GUI" "$PLIST" 2>/dev/null || true
}

cmd_autostart_off() {
  [[ -f "$PLIST" ]] || { err "LaunchAgent plist missing ($PLIST) — run: lm upgrade-ollama"; exit 1; }
  /usr/libexec/PlistBuddy -c "Set :RunAtLoad false" "$PLIST"
  /usr/libexec/PlistBuddy -c "Set :KeepAlive false" "$PLIST"
  _reload_service
  ok "autostart OFF — Ollama will not start at login (use: lm start)"
}

cmd_autostart_on() {
  [[ -f "$PLIST" ]] || { err "LaunchAgent plist missing ($PLIST) — run: lm upgrade-ollama"; exit 1; }
  /usr/libexec/PlistBuddy -c "Set :RunAtLoad true" "$PLIST"
  /usr/libexec/PlistBuddy -c "Set :KeepAlive true" "$PLIST"
  _reload_service
  ok "autostart ON — Ollama starts at login and stays resident"
}

cmd_status() {
  local rl ka
  rl="$(plist_bool RunAtLoad)"; ka="$(plist_bool KeepAlive)"
  echo "autostart : RunAtLoad=${rl:-?} KeepAlive=${ka:-?}$([[ -f "$PLIST" ]] || echo ' (no plist)')"
  if api_up; then
    echo "daemon    : running (pid $(pgrep -f '[o]llama serve' | head -1))"
  else
    echo "daemon    : stopped"
  fi
}

case "${1:-status}" in
  start)              cmd_start ;;
  stop)               cmd_stop ;;
  autostart)
    case "${2:-status}" in
      off)            cmd_autostart_off ;;
      on)             cmd_autostart_on ;;
      status)         cmd_status ;;
      *) echo "usage: lm autostart on|off|status"; exit 1 ;;
    esac ;;
  status)             cmd_status ;;
  -h|--help)          grep -E '^#( |=)' "$0" | sed 's/^# \{0,1\}//' ;;
  *) echo "usage: lm start|stop|autostart on|off|status"; exit 1 ;;
esac
