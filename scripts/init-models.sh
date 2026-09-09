#!/usr/bin/env bash
# =============================================================
# init-models.sh — hardware-driven manifest initialization
# =============================================================
# Phase 0: check software dependencies (scripts/lib/deps.sh); missing
#   engines (ollama / mflux / mlx-whisper / mlx-audio / espeak-ng) can be
#   auto-installed after a prompt, then the flow continues.
# Then: probe this Mac, match an exact SKU in config/hardware-profiles.tsv,
# or fall back to remote scoring (init-policy.conf). Writes config/*.manifest.
# Does not change lm update / lm deploy / lm get behavior.
#
# Usage:
#   lm init                     # deps → probe → match or score → confirm → write manifests
#   lm init --dry-run           # print deps + hardware + plan only (no install, no writes)
#   lm init --yes               # skip confirmations (also auto-installs missing deps)
#   lm init --deploy            # after write, lm deploy (+ pull image/asr/tts)
#   lm init --stack llm          # only models.manifest (default: all)
#   lm init --skip-deps          # skip the dependency check phase
#   lm init --ram 48 --chip "Apple M5 Max"
#
# Profiles: config/hardware-profiles.tsv + config/lineups.tsv
# Fallback policy: config/init-policy.conf (not used by lm update)
# Install SSOT remains: config/*.manifest
# =============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"
source "$ROOT/scripts/lib/deps.sh"
HW="$ROOT/scripts/lib/hw_profiles.py"
CHANGELOG="$ROOT/docs/changelog.md"

DRY_RUN=0
ASSUME_YES=0
DO_DEPLOY=0
SKIP_DEPS=0
RAM=""
CHIP=""
STACK="all"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --deploy) DO_DEPLOY=1; shift ;;
    --skip-deps) SKIP_DEPS=1; shift ;;
    --stack) STACK="${2:-}"; shift 2 ;;
    --stack=*) STACK="${1#--stack=}"; shift ;;
    --ram) RAM="${2:-}"; shift 2 ;;
    --ram=*) RAM="${1#--ram=}"; shift ;;
    --chip) CHIP="${2:-}"; shift 2 ;;
    --chip=*) CHIP="${1#--chip=}"; shift ;;
    -h|--help) grep -E '^#( |=)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1 (see --help)"; exit 1 ;;
  esac
done

command -v python3 >/dev/null 2>&1 || { err "python3 required"; exit 1; }
[[ -f "$HW" ]] || { err "missing $HW"; exit 1; }

# ---- Phase 0: software dependencies (engines, not weights) ----
if [[ "$SKIP_DEPS" -eq 1 ]]; then
  warn "skipped dependency check (--skip-deps)"
else
  [[ "$DRY_RUN" -eq 1 ]] || { ensure_weights_root || warn "weights root setup incomplete — continuing"; }
  DEP_STACKS=()
  if [[ "$STACK" == "all" ]]; then
    DEP_STACKS=(llm image asr tts)
  else
    IFS=',' read -ra DEP_STACKS <<< "$STACK"
  fi
  DEPS_ASSUME_YES="$ASSUME_YES" DEPS_DRY_RUN="$DRY_RUN" \
    deps_ensure "${DEP_STACKS[@]}" || warn "dependency check incomplete — continuing init"
fi

PLAN_ARGS=(plan --stack "$STACK")
[[ -n "$RAM" ]] && PLAN_ARGS+=(--ram "$RAM")
[[ -n "$CHIP" ]] && PLAN_ARGS+=(--chip "$CHIP")

log "Probing hardware and building init plan..."
JSON="$(python3 "$HW" "${PLAN_ARGS[@]}")" || { err "init plan failed"; exit 1; }

python3 -c '
import json, sys
sys.path.insert(0, sys.argv[1])
import hw_profiles
data = json.loads(sys.argv[2])
print(hw_profiles.format_plan(data))
' "$ROOT/scripts/lib" "$JSON"

ANY_CHANGED="$(python3 -c 'import json,sys; print(1 if json.loads(sys.argv[1]).get("any_changed") else 0)' "$JSON")"
SOURCE="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("source") or "")' "$JSON")"

if [[ "$ANY_CHANGED" -eq 0 ]]; then
  ok "Already initialized for this hardware ($SOURCE)"
  if [[ "$DO_DEPLOY" -eq 1 && "$DRY_RUN" -eq 0 ]]; then
    warn "No manifest changes; skipping deploy (pass lm deploy yourself if needed)"
  fi
  exit 0
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  warn "Dry-run only — manifests not modified"
  exit 0
fi

if [[ "$ASSUME_YES" -eq 0 ]]; then
  echo
  read -r -p "Write the proposed manifests? [y/N] " ans
  [[ "$ans" =~ ^[yY]$ ]] || { warn "Cancelled"; exit 0; }
fi

log "Writing config/*.manifest"
APPLY="$(python3 "$HW" apply "$JSON")"
python3 -c 'import json,sys; d=json.load(sys.stdin); print("\n".join("  - "+w for w in d.get("written") or []) or "  (no files changed)")' <<<"$APPLY"

TODAY="$(date +%Y-%m-%d)"
CHANGES_TXT="$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print("; ".join(d.get("changes") or []))' "$JSON")"
if [[ -n "$CHANGES_TXT" && -f "$CHANGELOG" ]]; then
  TMP="$(mktemp)"
  {
    echo "# Changelog"
    echo
    echo "## ${TODAY} (lm init: ${SOURCE})"
    echo
    echo "- \`lm init\` applied (${SOURCE}): ${CHANGES_TXT}"
    echo "- Install SSOT: \`config/*.manifest\`; profiles: \`config/hardware-profiles.tsv\`"
    echo
    tail -n +2 "$CHANGELOG"
  } > "$TMP"
  mv "$TMP" "$CHANGELOG"
  ok "Appended docs/changelog.md"
fi

if [[ "$DO_DEPLOY" -eq 1 ]]; then
  log "Deploying LLMs (ollama pull)..."
  "$ROOT/scripts/deploy.sh" || { err "deploy failed — manifests already updated"; exit 1; }
  if [[ "$STACK" == "all" || "$STACK" == *image* ]]; then
    log "Pulling image-gen weights..."
    awk -F'|' '$1 !~ /^#/ && $1 != "" && $1 != "retired" && NF>=3 { print $3 }' \
      "$ROOT/config/image-models.manifest" | while read -r repo; do
        [[ -n "$repo" ]] || continue
        "$ROOT/scripts/pull-hf-model.sh" --kind image "$repo" || warn "image pull failed: $repo"
      done
  fi
  if [[ "$STACK" == "all" || "$STACK" == *asr* || "$STACK" == *speech* ]]; then
    log "Pulling ASR weights..."
    awk -F'|' '$1 !~ /^#/ && $1 != "" && $1 != "retired" && NF>=3 { print $3 }' \
      "$ROOT/config/speech-models.manifest" | while read -r repo; do
        [[ -n "$repo" ]] || continue
        "$ROOT/scripts/pull-hf-model.sh" --kind speech "$repo" || warn "asr pull failed: $repo"
      done
  fi
  if [[ "$STACK" == "all" || "$STACK" == *tts* ]]; then
    log "Pulling TTS weights..."
    awk -F'|' '$1 !~ /^#/ && $1 != "" && $1 != "retired" && NF>=3 { print $3 }' \
      "$ROOT/config/tts-models.manifest" | while read -r repo; do
        [[ -n "$repo" ]] || continue
        "$ROOT/scripts/pull-hf-model.sh" --kind tts "$repo" || warn "tts pull failed: $repo"
      done
  fi
else
  warn "Skipped deploy — run: lm deploy"
fi

ok "Init complete ($SOURCE)"
