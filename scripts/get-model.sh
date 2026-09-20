#!/usr/bin/env bash
# =============================================================
# get-model.sh — fuzzy search + pull (+ optional tier assign)
# =============================================================
# Search ollama.com for a model by fuzzy name, interactively disambiguate
# when multiple families/tags match, then `ollama pull` and optionally
# write the chosen tag into config/models.manifest for a tier.
#
# Usage:
#   lm get qwen3.8
#   lm get "35b-a3b-q4"
#   lm get qwen3.5:9b
#   lm get ornith --tier main
#   lm get qwen --yes                 # auto-pick top match (non-interactive)
#   lm get qwen3.8 --tag q4_K_M       # constrain tag fuzzy filter
#   lm get qwen3.8 --dry-run          # resolve only, do not pull
#
# =============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"
CATALOG="$ROOT/scripts/lib/model_catalog.py"
MANIFEST="$ROOT/config/models.manifest"
POLICY="$ROOT/config/update-policy.conf"

QUERY=""
TIER=""
TAG_FILTER=""
ASSUME_YES=0
DRY_RUN=0
DO_PULL=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tier) TIER="${2:-}"; shift 2 ;;
    --tier=*) TIER="${1#--tier=}"; shift ;;
    --tag) TAG_FILTER="${2:-}"; shift 2 ;;
    --tag=*) TAG_FILTER="${1#--tag=}"; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --dry-run) DRY_RUN=1; DO_PULL=0; shift ;;
    --no-pull) DO_PULL=0; shift ;;
    -h|--help) grep -E '^#( |=)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)
      echo "Unknown argument: $1 (see --help)"; exit 1 ;;
    *)
      if [[ -z "$QUERY" ]]; then QUERY="$1"; else echo "Unexpected arg: $1"; exit 1; fi
      shift ;;
  esac
done

[[ -n "$QUERY" ]] || { err "usage: lm get <query> [--tier main|deep|fast|redteam|...]"; exit 1; }
if [[ -n "$TIER" ]] && ! is_known_llm_tier "$TIER"; then
  err "--tier must be one of: $KNOWN_LLM_TIERS"; exit 1
fi
command -v python3 >/dev/null 2>&1 || { err "python3 required"; exit 1; }
command -v ollama >/dev/null 2>&1 || { err "ollama not installed"; exit 1; }

pick_from_list() {
  # $1=prompt, remaining lines via stdin — prints chosen line
  local prompt="$1"
  local -a items=()
  local i line
  while IFS= read -r line; do
    [[ -n "$line" ]] && items+=("$line")
  done
  [[ ${#items[@]} -eq 0 ]] && return 1
  if [[ ${#items[@]} -eq 1 ]]; then
    echo "${items[0]}"
    return 0
  fi
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    echo "${items[0]}"
    return 0
  fi
  echo "$prompt" >&2
  for i in "${!items[@]}"; do
    printf '  [%d] %s\n' "$((i + 1))" "${items[$i]}" >&2
  done
  local ans
  while true; do
    read -r -p "Select [1-${#items[@]}] (or q to cancel): " ans
    [[ "$ans" =~ ^[qQ]$ ]] && return 2
    if [[ "$ans" =~ ^[0-9]+$ ]] && (( ans >= 1 && ans <= ${#items[@]} )); then
      echo "${items[$((ans - 1))]}"
      return 0
    fi
    echo "Invalid selection" >&2
  done
}

log "Searching remote library for: $QUERY"
SEARCH_JSON="$(python3 "$CATALOG" --policy "$POLICY" search "$QUERY")" || {
  err "search failed"; exit 1
}

#- With --yes, prefer families listed in update-policy FAMILIES
FAMILIES_TXT="$(SEARCH_JSON="$SEARCH_JSON" POLICY="$POLICY" ASSUME_YES="$ASSUME_YES" python3 <<'PY'
import json, os
from pathlib import Path

d = json.loads(os.environ["SEARCH_JSON"])
families = list(d.get("families") or [])
prefer = []
policy_path = Path(os.environ["POLICY"])
if policy_path.is_file():
    for line in policy_path.read_text(encoding="utf-8").splitlines():
        if line.startswith("FAMILIES="):
            prefer = [x.strip() for x in line.split("=", 1)[1].split(",") if x.strip()]
            break
if os.environ.get("ASSUME_YES") == "1" and prefer:
    ranked = [n for n in prefer if n in families] + [n for n in families if n not in prefer]
    families = ranked

for n in families:
    det = (d.get("family_details") or {}).get(n) or {}
    desc = (det.get("description") or "").replace("\n", " ")[:70]
    badges = ",".join(det.get("badges") or [])
    extra = ""
    if badges:
        extra = f"  [{badges}]"
    if desc:
        extra += f"  — {desc}"
    print(f"{n}{extra}")
PY
)"

if [[ -z "$FAMILIES_TXT" ]]; then
  err "No remote families matched '$QUERY'"
  exit 1
fi

FAMILY_LINE="$(printf '%s\n' "$FAMILIES_TXT" | pick_from_list "Multiple model families matched:")" || {
  [[ $? -eq 2 ]] && { warn "Cancelled"; exit 0; }
  err "No family selected"; exit 1
}
FAMILY="${FAMILY_LINE%% *}"
FAMILY="${FAMILY%%\[*}"
FAMILY="$(echo "$FAMILY" | xargs)"

#- Tag query: explicit --tag, or :suffix from original query, or tag-only search
TAG_QUERY="$TAG_FILTER"
if [[ -z "$TAG_QUERY" ]]; then
  TAG_QUERY="$(SEARCH_JSON="$SEARCH_JSON" QUERY="$QUERY" python3 <<'PY'
import json, os
d = json.loads(os.environ["SEARCH_JSON"])
if d.get("tag_only"):
    print(d.get("tag_query") or os.environ["QUERY"])
elif ":" in os.environ["QUERY"]:
    print(os.environ["QUERY"].split(":", 1)[1])
PY
)"
fi

log "Fetching tags for $FAMILY ..."
TAGS_JSON="$(python3 "$CATALOG" --policy "$POLICY" tags "$FAMILY" --tag-query "$TAG_QUERY")" || {
  err "failed to list tags"; exit 1
}

TAG_LINES="$(TAGS_JSON="$TAGS_JSON" python3 <<'PY'
import json, os
d = json.loads(os.environ["TAGS_JSON"])
for t in d.get("tags") or []:
    ctx = t.get("context") or "?"
    print(f"{t['full']:48} {t['size_gb']:6.1f}GB  ctx={ctx}")
PY
)"

if [[ -z "$TAG_LINES" ]]; then
  err "No tags matched for family '$FAMILY' (filter='${TAG_QUERY:-*}')"
  exit 1
fi

TAG_LINE="$(printf '%s\n' "$TAG_LINES" | pick_from_list "Multiple tags matched:")" || {
  [[ $? -eq 2 ]] && { warn "Cancelled"; exit 0; }
  err "No tag selected"; exit 1
}
FULL="$(echo "$TAG_LINE" | awk '{print $1}')"

echo
ok "Selected: $FULL"
echo "  $TAG_LINE"

if [[ "$DRY_RUN" -eq 1 ]]; then
  warn "Dry-run — not pulling"
  exit 0
fi

if [[ "$ASSUME_YES" -eq 0 ]]; then
  read -r -p "Pull and configure $FULL? [y/N] " ans
  [[ "$ans" =~ ^[yY]$ ]] || { warn "Cancelled"; exit 0; }
fi

if [[ "$DO_PULL" -eq 1 ]]; then
  log "ollama pull $FULL"
  ollama pull "$FULL"
  ok "Pulled $FULL"
fi

if [[ -n "$TIER" ]]; then
  log "Assigning $FULL -> tier $TIER in models.manifest"
  UPDATES_JSON="$(python3 -c 'import json,sys; print(json.dumps({sys.argv[1]: sys.argv[2]}))' "$TIER" "$FULL")"
  python3 "$CATALOG" --policy "$POLICY" --manifest "$MANIFEST" apply-manifest "$UPDATES_JSON" >/dev/null
  ok "Manifest updated ($TIER=$FULL). HF fallback URLs cleared for that row."
  warn "Other tiers unchanged. Run lm deploy $TIER if you want GGUF fallback path checked."
fi

"$ROOT/scripts/sync-registry.sh" || true
ok "Done. Try: lm run $FULL"
