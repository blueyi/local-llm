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

# Known LLM tier names (roles in config/models.manifest). A known tier that is
# absent from the manifest means this machine's lineup omits it — that is an
# error, NOT a tag to pass through to ollama (which would try to pull a
# nonexistent model named e.g. "deep").
KNOWN_LLM_TIERS="main deep fast embed chat reason rerank"

is_known_llm_tier() { [[ " $KNOWN_LLM_TIERS " == *" $1 "* ]]; }

# resolve_llm_tag <name> [manifest]
# stdout: ollama tag. Tier present -> its tag; known-but-absent tier ->
# guidance on stderr + return 1; anything else -> echoed as-is (raw tag).
resolve_llm_tag() {
  local name="$1" manifest="${2:-${ROOT:?ROOT not set}/config/models.manifest}" tag
  tag="$(awk -F'|' -v k="$name" '$1==k {print $2; exit}' "$manifest" 2>/dev/null)"
  if [[ -n "$tag" ]]; then
    echo "$tag"
    return 0
  fi
  if is_known_llm_tier "$name"; then
    err "tier '$name' is not listed in config/models.manifest (this lineup omits it)"
    echo "Available tiers:" >&2
    awk -F'|' '$1=="main"||$1=="deep"||$1=="fast"||$1=="embed"||$1=="chat"||$1=="reason"||$1=="rerank" {printf "  %-7s -> %s\n", $1, $2}' "$manifest" >&2
    echo "Or pass a full Ollama tag, e.g.: lm run qwen3.5:9b" >&2
    return 1
  fi
  echo "$name"
}
