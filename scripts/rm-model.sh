#!/usr/bin/env bash
# =============================================================
# rm-model.sh — remove an Ollama model via lm (not raw ollama rm)
# =============================================================
# Usage:
#   lm rm <name|tier>           # confirm, then ollama rm
#   lm rm <name|tier> --yes     # skip confirmation
#   lm rm qwen3.5:9b
#   lm rm fast                  # resolves tier from models.manifest
# =============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"
MANIFEST="$ROOT/config/models.manifest"

YES=0
NAME=""
for arg in "$@"; do
  case "$arg" in
    -y|--yes) YES=1 ;;
    -h|--help)
      # Header-only help (stop before runtime code; skip shebang)
      awk 'BEGIN{p=1} /^#!/ {next} /^set -euo pipefail/{exit} /^#/{sub(/^# ?/,""); print}' "$0"
      exit 0
      ;;
    -*)
      echo "Unknown flag: $arg (see --help)"
      exit 1
      ;;
    *)
      if [[ -n "$NAME" ]]; then
        echo "Usage: lm rm <name|tier> [--yes]"
        exit 1
      fi
      NAME="$arg"
      ;;
  esac
done

if [[ -z "$NAME" ]]; then
  echo "Usage: lm rm <name|tier> [--yes]"
  echo "  Removes a local Ollama model (same as ollama rm, with confirmation)."
  exit 1
fi

command -v ollama >/dev/null 2>&1 || { echo "ERROR: ollama not installed"; exit 1; }

# Resolve tier name -> manifest tag
TAG="$NAME"
if [[ -f "$MANIFEST" ]] && grep -qE "^${NAME}\|" "$MANIFEST" 2>/dev/null; then
  TAG="$(manifest_value "$MANIFEST" "$NAME" 2)"
fi

if ! ollama list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$TAG"; then
  err "model not installed: $TAG"
  if [[ "$TAG" != "$NAME" ]]; then
    echo "       (resolved from tier '$NAME')"
  fi
  exit 1
fi

# Warn when removing a currently manifest-listed model
IN_MANIFEST=0
MANIFEST_TIERS=""
if [[ -f "$MANIFEST" ]]; then
  while IFS='|' read -r tier tag _; do
    [[ "$tier" =~ ^#|^$ ]] && continue
    [[ "$tier" == "retired" ]] && continue
    tag="$(echo "$tag" | xargs)"
    if [[ "$tag" == "$TAG" ]]; then
      IN_MANIFEST=1
      MANIFEST_TIERS="${MANIFEST_TIERS:+$MANIFEST_TIERS, }$tier"
    fi
  done < "$MANIFEST"
fi

echo "About to remove Ollama model: $TAG"
if [[ "$IN_MANIFEST" -eq 1 ]]; then
  echo "WARNING: this tag is still listed in models.manifest as: $MANIFEST_TIERS"
  echo "         After removal, run: lm deploy  (or lm deploy --force) to reinstall."
fi
SIZE="$(ollama list 2>/dev/null | awk -v t="$TAG" 'NR>1 && $1==t {print $3,$4; exit}')"
[[ -n "$SIZE" ]] && echo "Size (from ollama list): $SIZE"

if [[ "$YES" -eq 0 ]]; then
  read -r -p "Confirm deletion? [y/N] " ans
  [[ "$ans" =~ ^[yY]$ ]] || { echo "Cancelled."; exit 0; }
fi

ollama rm "$TAG"
echo "OK: removed $TAG"
"$ROOT/scripts/sync-registry.sh" || true
