#!/usr/bin/env bash
# status.sh — local model stack overview (lm status)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"
MODELS_ROOT="$HOME/models"
GGUF_DIR="${LLM_GGUF_DIR:-$MODELS_ROOT/gguf}"
MANIFEST="$ROOT/config/models.manifest"

# Role → short scenario label (display only; SSOT remains models.manifest)
scenario_for() {
  case "$1" in
    main)   echo "Agent / coding / vision" ;;
    deep)   echo "Hard bugs / quality" ;;
    fast)   echo "Draft / completion" ;;
    embed)  echo "RAG retrieval" ;;
    rerank) echo "RAG rerank" ;;
    chat)   echo "Creative / multilingual" ;;
    reason) echo "Dedicated reasoning" ;;
    *)      echo "—" ;;
  esac
}

# Print SIZE column from `ollama list` for a tag (e.g. "17 GB")
ollama_size_for() {
  local tag="$1"
  ollama list 2>/dev/null | awk -v t="$tag" 'NR>1 && $1==t {
    if (NF>=4) print $3,$4; else print "?"
    exit
  }'
}

echo "=== local-llm status ==="
echo "Knowledge base: $ROOT"
echo

echo "--- Unified weights root ($MODELS_ROOT) ---"
if [ -d "$MODELS_ROOT" ]; then
  du -sh "$MODELS_ROOT"/* 2>/dev/null || echo "(empty)"
  for link in "$HOME/.ollama/models" "$HOME/.lmstudio/models/llm-gguf"; do
    if [ -L "$link" ]; then
      tgt="$(readlink "$link")"
      if [ -e "$link" ]; then echo "link OK: $link -> $tgt"; else echo "link BROKEN: $link -> $tgt"; fi
    elif [ -e "$link" ]; then
      echo "link missing (plain path): $link"
    fi
  done
else
  echo "(missing - weights root not initialized)"
fi
echo

# ---- Scenario roles (SSOT: models.manifest) ----
echo "--- Scenario roles (models.manifest) ---"
if [ ! -f "$MANIFEST" ]; then
  echo "(missing manifest)"
elif ! command -v ollama >/dev/null 2>&1; then
  echo "Ollama: not installed"
else
  printf '  %-8s %-28s %-42s %s\n' "ROLE" "SCENARIO" "MODEL" "LOCAL"
  printf '  %-8s %-28s %-42s %s\n' "----" "--------" "-----" "-----"
  while IFS='|' read -r tier tag _ctx _url _mm; do
    case "$tier" in \#*|""|retired) continue ;; esac
    tag="$(echo "$tag" | xargs)"
    [[ -z "$tag" ]] && continue
    sc="$(scenario_for "$tier")"
    if installed_tags | grep -qx "$tag"; then
      sz="$(ollama_size_for "$tag")"
      printf '  %-8s %-28s %-42s ✓ %s\n' "$tier" "$sc" "$tag" "${sz:-installed}"
    else
      printf '  %-8s %-28s %-42s ✗ missing (lm deploy %s)\n' "$tier" "$sc" "$tag" "$tier"
    fi
  done < "$MANIFEST"
fi
echo

if command -v ollama >/dev/null 2>&1; then
  echo "Ollama: $(ollama --version 2>/dev/null || echo unknown)"
  echo "--- ollama list (all local; ROLE = active manifest tier) ---"
  printf '  %-8s %-42s %10s  %s\n' "ROLE" "NAME" "SIZE" "NOTE"
  printf '  %-8s %-42s %10s  %s\n' "----" "----" "----" "----"
  ollama list 2>/dev/null | awk 'NR>1 {
    name=$1; size=$3" "$4
    print name "\t" size
  }' | while IFS=$'\t' read -r name size; do
    [[ -z "$name" ]] && continue
    role="—"
    note=""
    if [[ -f "$MANIFEST" ]]; then
      while IFS='|' read -r tier tag _; do
        case "$tier" in \#*|""|retired) continue ;; esac
        tag="$(echo "$tag" | xargs)"
        if [[ "$tag" == "$name" ]]; then
          role="$tier"
          break
        fi
      done < "$MANIFEST"
      if [[ "$role" == "—" ]]; then
        if grep -E "^retired\|" "$MANIFEST" | cut -d'|' -f2 | grep -qx "$name"; then
          role="retired"
          note="prune candidate (lm deploy --prune)"
        else
          note="extra (not in active roles)"
        fi
      fi
    fi
    printf '  %-8s %-42s %10s  %s\n' "$role" "$name" "$size" "$note"
  done
  echo "--- ollama ps (currently loaded) ---"
  ollama ps 2>/dev/null || true
else
  echo "Ollama: not installed"
fi
echo

# --- GGUF / LM Studio ---
echo "--- GGUF (LM Studio) ---"
echo "dir: $GGUF_DIR"
gguf_human() { du -h "$1" 2>/dev/null | awk '{print $1}'; }
gguf_bytes() { stat -f%z "$1" 2>/dev/null || echo 0; }
gguf_manifest_note() {
  local name="$1" tier tag _c url _m
  [[ -f "$MANIFEST" ]] || { echo "(not in manifest)"; return; }
  while IFS='|' read -r tier tag _c url _m; do
    case "$tier" in \#*|""|retired) continue ;; esac
    [[ -z "${url:-}" ]] && continue
    if [[ "$(basename "$url")" == "$name" ]]; then
      echo "[$tier] $tag"
      return
    fi
  done < "$MANIFEST"
  echo "(not in manifest)"
}

if [ ! -d "$GGUF_DIR" ]; then
  echo "(missing - run: lm pull-gguf main deep fast --link)"
elif ! find "$GGUF_DIR" -maxdepth 1 -name '*.gguf' -type f 2>/dev/null | grep -q .; then
  echo "(empty - run: lm pull-gguf main deep fast --link)"
else
  printf '  %-48s %8s  %-12s  %s\n' "FILE" "SIZE" "MMPROJ" "MANIFEST"
  printf '  %-48s %8s  %-12s  %s\n' "----" "----" "------" "--------"

  find "$GGUF_DIR" -maxdepth 1 -name '*.gguf' -type f 2>/dev/null | sort | while read -r f; do
    name="$(basename "$f")"
    case "$name" in
      *.mmproj*.gguf|*mmproj-F16.gguf) continue ;;
    esac
    size="$(gguf_human "$f")"
    bytes="$(gguf_bytes "$f")"
    stem="${name%.gguf}"
    mmproj="no"
    for cand in \
      "$GGUF_DIR/${stem}.mmproj-F16.gguf" \
      "$GGUF_DIR/${stem}.mmproj.gguf" \
      "$GGUF_DIR/mmproj-F16.gguf"
    do
      if [ -f "$cand" ]; then
        mmsz="$(gguf_human "$cand")"
        mmproj="yes ($mmsz)"
        break
      fi
    done
    mnote="$(gguf_manifest_note "$name")"
    # Incomplete: active-tier weight under ~2GB is almost certainly a partial download
    if [[ "$mnote" == \[* ]] && [[ "$bytes" -lt 2000000000 ]]; then
      mnote="$mnote ⚠ INCOMPLETE (lm pull-gguf)"
    fi
    printf '  %-48s %8s  %-12s  %s\n' "$name" "$size" "$mmproj" "$mnote"
  done

  orphan_tmp="$(mktemp)"
  find "$GGUF_DIR" -maxdepth 1 -name '*.gguf' -type f 2>/dev/null | sort | while read -r f; do
    name="$(basename "$f")"
    case "$name" in
      *.mmproj-F16.gguf) stem="${name%.mmproj-F16.gguf}" ;;
      *.mmproj.gguf) stem="${name%.mmproj.gguf}" ;;
      *) continue ;;
    esac
    if [ ! -f "$GGUF_DIR/${stem}.gguf" ]; then
      mmsz="$(gguf_human "$f")"
      echo "    - $name ($mmsz)" >> "$orphan_tmp"
    fi
  done
  if [ -s "$orphan_tmp" ]; then
    echo "  orphan mmproj:"
    cat "$orphan_tmp"
  fi
  rm -f "$orphan_tmp"

  echo "  total: $(du -sh "$GGUF_DIR" 2>/dev/null | awk '{print $1}')  (lm pull-gguf to refresh)"
fi
echo

echo "--- Image generation (mflux) ---"
if command -v mflux-generate-flux2 >/dev/null 2>&1; then
  echo "mflux: installed ($(command -v mflux-generate-flux2))"
else
  echo "mflux: not installed (uv tool install mflux)"
fi
if [ -f "$ROOT/config/image-models.manifest" ]; then
  grep -E '^(primary|alt)\|' "$ROOT/config/image-models.manifest" | while IFS='|' read -r role id repo _; do
    d="$MODELS_ROOT/image-gen/$(basename "$repo")"
    if [ -d "$d" ]; then echo "  ✓ [$role] $id ($(du -sh "$d" 2>/dev/null | awk '{print $1}'))"; else echo "  ✗ [$role] $id (weights missing: lm pull-image $repo)"; fi
  done
fi
echo

echo "--- Speech ASR (mlx-whisper) ---"
if command -v mlx_whisper >/dev/null 2>&1; then
  echo "mlx_whisper: installed ($(command -v mlx_whisper))"
else
  echo "mlx_whisper: not installed (uv tool install mlx-whisper)"
fi
if [ -f "$ROOT/config/speech-models.manifest" ]; then
  grep -E '^(primary|alt)\|' "$ROOT/config/speech-models.manifest" | while IFS='|' read -r role id repo _; do
    d="$MODELS_ROOT/speech/$(basename "$repo")"
    if [ -f "$d/weights.safetensors" ] || [ -d "$d" ]; then
      echo "  ✓ [$role] $id ($(du -sh "$d" 2>/dev/null | awk '{print $1}'))"
    else
      echo "  ✗ [$role] $id (weights missing: lm pull-speech $repo)"
    fi
  done
fi
echo

echo "--- Speech TTS (mlx-audio) ---"
if command -v mlx_audio.tts.generate >/dev/null 2>&1; then
  echo "mlx_audio.tts: installed ($(command -v mlx_audio.tts.generate))"
else
  echo "mlx_audio.tts: not installed (uv tool install mlx-audio --with 'misaki[en]' --with 'misaki[zh]')"
fi
if [ -f "$ROOT/config/tts-models.manifest" ]; then
  grep -E '^(primary|alt)\|' "$ROOT/config/tts-models.manifest" | while IFS='|' read -r role id repo _; do
    d="$MODELS_ROOT/tts/$(basename "$repo")"
    if [ -f "$d/config.json" ]; then
      echo "  ✓ [$role] $id ($(du -sh "$d" 2>/dev/null | awk '{print $1}'))"
    else
      echo "  ✗ [$role] $id (weights missing: lm pull-tts $repo)"
    fi
  done
fi
echo

echo "--- Disk (Data volume) ---"
df -h /System/Volumes/Data 2>/dev/null | tail -1 || df -h / | tail -1
