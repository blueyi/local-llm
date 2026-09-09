#!/usr/bin/env bash
# =============================================================
# upgrade-ollama.sh — check / install / upgrade Ollama to GitHub latest
# =============================================================
# Used by `lm init` (dependency phase), `lm deploy` (preflight) and
# `lm upgrade-ollama`. Handles fresh machines: when Ollama is missing
# entirely, offers to install the latest release (same install target).
#
# Usage:
#   lm upgrade-ollama                 # check; if missing/outdated, prompt then install/upgrade
#   lm upgrade-ollama --yes           # install/upgrade without prompt
#   lm upgrade-ollama --check-only    # report only (exit 0=current, 2=outdated, 3=not installed)
#   lm upgrade-ollama --upgrade       # force install/upgrade to latest (no prompt)
#
# Install target (darwin): /opt/homebrew/opt/ollama-upstream
#   (brew formula often lags behind ollama.com / GitHub releases)
# =============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"
UPSTREAM_DIR="${OLLAMA_UPSTREAM_DIR:-/opt/homebrew/opt/ollama-upstream}"
GH_LATEST_API="https://api.github.com/repos/ollama/ollama/releases/latest"
GH_ASSET_BASE="https://github.com/ollama/ollama/releases/download"

MODE="prompt"   # prompt | yes | check-only | upgrade
for arg in "$@"; do
  case "$arg" in
    --check-only|--check) MODE="check-only" ;;
    --yes|-y)             MODE="yes" ;;
    --upgrade|--force)    MODE="upgrade" ;;
    -h|--help)
      awk '/^#!/ {next} /^set -euo pipefail/{exit} /^#/{sub(/^# ?/,""); print}' "$0"
      exit 0
      ;;
    *) echo "Unknown argument: $arg (see --help)"; exit 1 ;;
  esac
done

# Strip leading v; keep digits and dots only
normalize_ver() {
  echo "$1" | sed -E 's/^[vV]//; s/[^0-9.].*$//'
}

# true if $1 < $2 (semver-ish via sort -V)
ver_lt() {
  local a b
  a="$(normalize_ver "$1")"
  b="$(normalize_ver "$2")"
  [[ -n "$a" && -n "$b" && "$a" != "$b" && "$(printf '%s\n' "$a" "$b" | sort -V | head -1)" == "$a" ]]
}

current_ollama_version() {
  local v=""
  # Prefer daemon version when online (what actually serves pulls)
  if curl -s -m 3 -o /tmp/ollama-api-ver.$$ "http://127.0.0.1:11434/api/version" 2>/dev/null; then
    v="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version",""))' /tmp/ollama-api-ver.$$ 2>/dev/null || true)"
    rm -f /tmp/ollama-api-ver.$$
  fi
  if [[ -z "$v" ]] && command -v ollama >/dev/null 2>&1; then
    v="$(ollama --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  fi
  echo "$v"
}

fetch_latest_version() {
  local json tag
  json="$(curl -fsSL -m 20 -H 'Accept: application/vnd.github+json' "$GH_LATEST_API")" || return 1
  tag="$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag_name",""))' 2>/dev/null || true)"
  [[ -n "$tag" ]] || return 1
  normalize_ver "$tag"
}

restart_daemon() {
  local plist="$HOME/Library/LaunchAgents/homebrew.mxcl.ollama.plist"
  local bin="$UPSTREAM_DIR/ollama"
  [[ -x "$bin" ]] || bin="$(command -v ollama || true)"

  if [[ -f "$plist" ]]; then
    /usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 $bin" "$plist" 2>/dev/null || true
    launchctl bootout "gui/$(id -u)/homebrew.mxcl.ollama" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null || true
    launchctl kickstart -k "gui/$(id -u)/homebrew.mxcl.ollama" 2>/dev/null || true
  else
    # Minimal plist so KeepAlive survives reboot
    mkdir -p "$HOME/Library/LaunchAgents" /opt/homebrew/var/log
    cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>EnvironmentVariables</key>
  <dict>
    <key>OLLAMA_FLASH_ATTENTION</key>
    <string>1</string>
    <key>OLLAMA_KV_CACHE_TYPE</key>
    <string>q8_0</string>
  </dict>
  <key>KeepAlive</key>
  <true/>
  <key>Label</key>
  <string>homebrew.mxcl.ollama</string>
  <key>ProgramArguments</key>
  <array>
    <string>${bin}</string>
    <string>serve</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardErrorPath</key>
  <string>/opt/homebrew/var/log/ollama.log</string>
  <key>StandardOutPath</key>
  <string>/opt/homebrew/var/log/ollama.log</string>
  <key>WorkingDirectory</key>
  <string>/opt/homebrew/var</string>
</dict>
</plist>
EOF
    launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null || true
    launchctl kickstart -k "gui/$(id -u)/homebrew.mxcl.ollama" 2>/dev/null || true
  fi

  # Fallback if launchd didn't bring it up
  if ! curl -s -m 2 -o /dev/null "http://127.0.0.1:11434/api/tags"; then
    pkill -f '[o]llama serve' 2>/dev/null || true
    sleep 1
    nohup "$bin" serve >/opt/homebrew/var/log/ollama.log 2>&1 &
  fi

  local i
  for i in $(seq 1 20); do
    if curl -s -m 2 -o /dev/null "http://127.0.0.1:11434/api/tags"; then
      ok "daemon online (v$(current_ollama_version))"
      return 0
    fi
    sleep 1
  done
  err "daemon did not come up after upgrade"
  return 1
}

install_darwin_release() {
  local ver="$1"
  local tag="v${ver}"
  local tmp tgz sum expected

  # Install target + PATH symlink both live under the Homebrew prefix
  if [[ ! -d /opt/homebrew/bin ]]; then
    err "Homebrew prefix /opt/homebrew missing — install Homebrew first, or install Ollama manually: https://ollama.com/download"
    return 1
  fi

  tmp="$(mktemp -d /tmp/ollama-upgrade.XXXXXX)"
  tgz="$tmp/ollama-darwin.tgz"

  log "Downloading Ollama ${tag} (darwin)..."
  curl -fL --retry 3 --retry-delay 2 -o "$tgz" "${GH_ASSET_BASE}/${tag}/ollama-darwin.tgz"

  if curl -fsSL -m 30 -o "$tmp/sha256sum.txt" "${GH_ASSET_BASE}/${tag}/sha256sum.txt"; then
    expected="$(awk '/ollama-darwin\.tgz$/ {print $1; exit}' "$tmp/sha256sum.txt")"
    if [[ -n "$expected" ]]; then
      echo "${expected}  ${tgz}" | shasum -a 256 -c -
    else
      warn "sha256sum.txt has no ollama-darwin.tgz entry — skipping checksum"
    fi
  else
    warn "could not fetch sha256sum.txt — skipping checksum"
  fi

  log "Extracting to $UPSTREAM_DIR"
  # Stop brew-managed service if present (may remove plist; we recreate)
  if command -v brew >/dev/null 2>&1; then
    brew services stop ollama 2>/dev/null || true
  fi
  pkill -f '[o]llama serve' 2>/dev/null || true
  sleep 1

  rm -rf "$UPSTREAM_DIR"
  mkdir -p "$UPSTREAM_DIR"
  tar xzf "$tgz" -C "$UPSTREAM_DIR"
  chmod +x "$UPSTREAM_DIR/ollama" 2>/dev/null || true
  [[ -x "$UPSTREAM_DIR/llama-server" ]] && chmod +x "$UPSTREAM_DIR/llama-server"
  [[ -x "$UPSTREAM_DIR/llama-quantize" ]] && chmod +x "$UPSTREAM_DIR/llama-quantize"

  # Prefer upstream on PATH
  if [[ -d /opt/homebrew/bin ]]; then
    if [[ -e /opt/homebrew/bin/ollama && ! -L /opt/homebrew/bin/ollama ]]; then
      mv /opt/homebrew/bin/ollama "/opt/homebrew/bin/ollama.bak-$(date +%Y%m%d)" 2>/dev/null || true
    elif [[ -L /opt/homebrew/bin/ollama ]]; then
      # Keep a bak of previous brew link once
      [[ -e /opt/homebrew/bin/ollama.brew.bak ]] || \
        cp -P /opt/homebrew/bin/ollama /opt/homebrew/bin/ollama.brew.bak 2>/dev/null || true
    fi
    ln -sfn "$UPSTREAM_DIR/ollama" /opt/homebrew/bin/ollama
  fi

  hash -r 2>/dev/null || true
  restart_daemon

  local now
  now="$(current_ollama_version)"
  if ver_lt "$now" "$ver"; then
    err "upgrade finished but still running $now (wanted $ver)"
    rm -rf "$tmp"
    return 1
  fi
  ok "Ollama upgraded to $now"
  rm -rf "$tmp"
}

do_upgrade() {
  local latest="$1"
  case "$(uname -s)" in
    Darwin) install_darwin_release "$latest" ;;
    *)
      err "auto-upgrade only implemented for macOS (darwin); install from https://ollama.com/download"
      return 1
      ;;
  esac
}

# ---- main ----
CURRENT="$(current_ollama_version || true)"

log "Checking latest Ollama release (GitHub)..."
LATEST="$(fetch_latest_version || true)"

# Fresh-install path: no local binary and no daemon answering
if [[ -z "$CURRENT" ]]; then
  if [[ -z "$LATEST" || ! "$LATEST" =~ ^[0-9]+\.[0-9]+ ]]; then
    err "Ollama not installed and latest release unknown (offline?) — install manually: https://ollama.com/download"
    exit 1
  fi
  warn "Ollama is not installed (latest: $LATEST)"
  case "$MODE" in
    check-only) exit 3 ;;
    yes|upgrade) do_upgrade "$LATEST"; exit $? ;;
  esac
  if [[ ! -t 0 ]]; then
    err "non-interactive stdin — re-run 'lm upgrade-ollama --upgrade' to auto-install"
    exit 1
  fi
  read -r -p "Install Ollama $LATEST now? [Y/n] " ans
  ans="${ans:-Y}"
  if [[ "$ans" =~ ^[yY]$ ]]; then
    do_upgrade "$LATEST"
  else
    warn "Skipped Ollama install"
  fi
  exit 0
fi

# Installed path: only version comparison below
if [[ -z "$LATEST" || ! "$LATEST" =~ ^[0-9]+\.[0-9]+ ]]; then
  warn "could not fetch latest version from GitHub — continuing with local $CURRENT"
  exit 0
fi

ok "local=$CURRENT  latest=$LATEST"

if ! ver_lt "$CURRENT" "$LATEST"; then
  ok "Ollama is up to date"
  exit 0
fi

warn "Ollama is outdated: $CURRENT < $LATEST"

if [[ "$MODE" == "check-only" ]]; then
  exit 2
fi

if [[ "$MODE" == "upgrade" || "$MODE" == "yes" ]]; then
  do_upgrade "$LATEST"
  exit $?
fi

# prompt mode
if [[ ! -t 0 ]]; then
  warn "non-interactive stdin — skip Ollama upgrade (pass --yes to auto-upgrade)"
  exit 0
fi

read -r -p "Update Ollama to $LATEST before deploy? [Y/n] " ans
ans="${ans:-Y}"
if [[ "$ans" =~ ^[yY]$ ]]; then
  do_upgrade "$LATEST"
else
  warn "Skipping Ollama upgrade — continuing with $CURRENT"
fi
