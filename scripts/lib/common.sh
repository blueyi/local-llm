#!/usr/bin/env bash
# Shared shell helpers for the lm implementation scripts.

# Keep this file source-only; callers own set -euo pipefail and ROOT.

log()  { printf '\033[1;36m>>> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!! %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m OK %s\033[0m\n' "$*"; }
err()  { printf '\033[1;31mERR %s\033[0m\n' "$*" >&2; }

trim() { printf '%s' "$1" | xargs; }

manifest_value() {
  local manifest="$1" key="$2" column="$3"
  awk -F'|' -v key="$key" -v column="$column" \
    '$1 !~ /^#/ && $1 != "" && $1 != "retired" && $2 == key { print $column; exit }' \
    "$manifest"
}

manifest_primary_value() {
  local manifest="$1" column="$2"
  awk -F'|' -v column="$column" \
    '$1 == "primary" { print $column; exit }' "$manifest"
}

installed_tags() {
  ollama list 2>/dev/null | awk 'NR > 1 { print $1 }'
}

require_cmd() {
  local cmd="$1" hint="${2:-$1}"
  command -v "$cmd" >/dev/null 2>&1 || { err "$hint"; return 1; }
}
