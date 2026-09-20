#!/usr/bin/env bash
# =============================================================
# smoke-test.sh — model smoke test: LLM reply + tok/s, embeddings, image-gen
# =============================================================
# Usage:
#   lm test                    # test the main LLM tier
#   lm test fast               # any known LLM tier (main|deep|fast|redteam|...)
#   lm test all                # all LLM roles + image + speech (ASR+TTS)
#   lm test all-llm            # all LLM roles only
#   lm test all-image          # all image-gen models only
#   lm test asr                # speech ASR smoke (mlx-whisper)
#   lm test tts                # speech TTS smoke (mlx-audio / Kokoro)
#   lm test qwen3.5:9b         # or any installed ollama tag (see: ollama list)
#   lm test fast "1+1=?"       # custom prompt as 2nd arg (LLM / embed runs only)
#
# The model argument accepts:
#   all                        -> LLM roles + image + speech
#   all-llm | all-image        -> scope to one manifest
#   asr | tts                  -> speech ASR / TTS smoke
#   <known LLM tier>           -> config/models.manifest
#   <any ollama tag>           -> used as-is
#
# Notes on 'all':
#   - Chat/LLM models run SEQUENTIALLY with keep_alive=0 so each unloads after
#     its test — two large models never coexist in RAM (48GB budget).
#   - embed uses /api/embeddings; rerank uses a short generate ranking prompt.
#   - Image models generate a small 512x512 test image into a temp dir.
#   - asr transcribes a 1s tone via mlx-whisper (engine smoke, not content QA).
#   - tts synthesizes a short English phrase via mlx-audio (engine smoke).
# =============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"
MANIFEST="$ROOT/config/models.manifest"
IMG_MANIFEST="$ROOT/config/image-models.manifest"
SPEECH_MANIFEST="$ROOT/config/speech-models.manifest"
SPEECH_ROOT="${LLM_SPEECH_DIR:-$HOME/models/speech}"
TTS_MANIFEST="$ROOT/config/tts-models.manifest"
TTS_ROOT="${LLM_TTS_DIR:-$HOME/models/tts}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  grep -E '^#( |=)' "$0" | sed 's/^# \{0,1\}//'
  echo "Available LLM roles (config/models.manifest):"
  print_available_llm_tiers "$MANIFEST"
  echo
  echo "Image-gen models (config/image-models.manifest):"
  grep -E '^(primary|alt)\|' "$IMG_MANIFEST" | awk -F'|' '{printf "  %-8s -> %s\n", $1, $2}'
  echo
  echo "Speech ASR (config/speech-models.manifest):"
  grep -E '^(primary|alt)\|' "$SPEECH_MANIFEST" | awk -F'|' '{printf "  %-8s -> %s\n", $1, $2}'
  echo
  echo "Speech TTS (config/tts-models.manifest):"
  grep -E '^(primary|alt)\|' "$TTS_MANIFEST" | awk -F'|' '{printf "  %-8s -> %s\n", $1, $2}'
  echo
  echo "Installed ollama tags:"
  ollama list 2>/dev/null | awk 'NR>1{print "  "$1}' || echo "  (daemon not running)"
  exit 0
fi

MODEL="${1:-main}"
PROMPT="${2:-Introduce yourself in one sentence. /no_think}"

## test_one <tag> <prompt> [keep_alive] — one LLM smoke test: reply + tok/s
test_one() {
  local tag="$1" prompt="$2" keep="${3:-}"
  echo "Smoke test (LLM): $tag"
  local body
  body="$(SM_MODEL="$tag" SM_PROMPT="$prompt" SM_KEEP="$keep" python3 -c '
import json, os
req = {"model": os.environ["SM_MODEL"], "prompt": os.environ["SM_PROMPT"], "stream": False}
if os.environ.get("SM_KEEP") != "":
    req["keep_alive"] = int(os.environ["SM_KEEP"])
print(json.dumps(req))')"
  curl -s http://127.0.0.1:11434/api/generate -d "$body" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if "error" in d:
    print("ERROR:", d["error"]); sys.exit(1)
tps = d["eval_count"] / (d["eval_duration"] / 1e9)
load = d.get("load_duration", 0) / 1e9
ec = d["eval_count"]
print("Reply:", d["response"].strip()[:120])
print(f"Speed: {tps:.1f} tok/s  (load {load:.1f}s, generated {ec} tok)")
'
}

## test_embed_one <tag> <prompt> — embedding smoke test
test_embed_one() {
  local tag="$1" prompt="${2:-local-llm embedding smoke test}"
  echo "Smoke test (embed): $tag"
  local body
  body="$(python3 -c 'import json,sys; print(json.dumps({"model":sys.argv[1],"prompt":sys.argv[2]}))' "$tag" "$prompt")"
  curl -s http://127.0.0.1:11434/api/embeddings -d "$body" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if "error" in d:
    print("ERROR:", d["error"]); sys.exit(1)
emb = d.get("embedding") or []
if not emb:
    print("ERROR: empty embedding"); sys.exit(1)
print(f"Embedding dims: {len(emb)}  sample=[{emb[0]:.4f}, {emb[1]:.4f}, ...]")
'
}

## test_rerank_one <tag> — reranker smoke (short generate; expects a score-ish reply)
test_rerank_one() {
  local tag="$1"
  local prompt='Given query "apple" and document "A red fruit grows on trees", output only a relevance score from 0 to 1.'
  echo "Smoke test (rerank): $tag"
  test_one "$tag" "$prompt" 0
}

## test_asr_one — speech ASR engine smoke
test_asr_one() {
  local id repo path wav
  id="$(awk -F'|' '/^primary\|/{print $2; exit}' "$SPEECH_MANIFEST")"
  repo="$(awk -F'|' '/^primary\|/{print $3; exit}' "$SPEECH_MANIFEST")"
  path="$SPEECH_ROOT/$(basename "$repo")"
  echo "Smoke test (asr): $id"
  [[ -f "$path/weights.safetensors" ]] || {
    echo "ERROR: ASR weights missing at $path (lm pull-speech)"; return 1
  }
  command -v mlx_whisper >/dev/null 2>&1 || {
    echo "ERROR: mlx_whisper missing (uv tool install mlx-whisper)"; return 1
  }
  wav="$SPEECH_ROOT/smoke-tone.wav"
  if [[ ! -f "$wav" ]]; then
    command -v ffmpeg >/dev/null 2>&1 || { echo "ERROR: ffmpeg required for ASR smoke"; return 1; }
    ffmpeg -y -f lavfi -i 'sine=frequency=440:duration=1' -ar 16000 "$wav" >/dev/null 2>&1
  fi
  local out; out="$(mktemp -d)/asr"
  if "$ROOT/scripts/asr.sh" "$wav" --model "$id" -o "$out" >/dev/null 2>&1 \
     && find "$out" -name '*.txt' | grep -q .; then
    echo "ASR OK: wrote transcript under $out (engine reachable)"
    return 0
  fi
  echo "ERROR: ASR smoke failed"; return 1
}

## test_tts_one — speech TTS engine smoke
test_tts_one() {
  local id repo path out
  id="$(awk -F'|' '/^primary\|/{print $2; exit}' "$TTS_MANIFEST")"
  repo="$(awk -F'|' '/^primary\|/{print $3; exit}' "$TTS_MANIFEST")"
  path="$TTS_ROOT/$(basename "$repo")"
  echo "Smoke test (tts): $id"
  [[ -f "$path/config.json" ]] || {
    echo "ERROR: TTS weights missing at $path (lm pull-tts)"; return 1
  }
  command -v mlx_audio.tts.generate >/dev/null 2>&1 || {
    echo "ERROR: mlx_audio.tts.generate missing (uv tool install mlx-audio)"; return 1
  }
  out="$(mktemp -d)/tts"
  if "$ROOT/scripts/tts.sh" "Hello from local TTS smoke test." --model "$id" \
       --voice af_heart --lang a -o "$out" >/dev/null 2>&1 \
     && find "$out" -type f \( -name '*.wav' -o -name '*.mp3' -o -name '*.flac' \) | grep -q .; then
    echo "TTS OK: wrote audio under $out (engine reachable)"
    return 0
  fi
  echo "ERROR: TTS smoke failed"; return 1
}

## test_image_one <model-id> — one image-gen smoke test: 512px, fixed seed, temp output
test_image_one() {
  local id="$1"
  local out; out="$(mktemp -d)/smoke-$id.png"
  echo "Smoke test (image): $id"
  local t0 t1
  t0=$(date +%s)
  if "$ROOT/scripts/gen-image.sh" --model "$id" --size 512x512 --seed 7 --out "$out" \
       "a small red bird on a green branch, simple background" >/dev/null 2>&1 \
     && [[ -s "$out" ]]; then
    t1=$(date +%s)
    echo "Image: $out ($(du -h "$out" | awk '{print $1}'), $((t1 - t0))s)"
    return 0
  fi
  echo "ERROR: image generation failed for $id (run manually: lm image --model $id \"test\")"
  return 1
}

run_all_llm() {
  local fail=0 tier tag _
  while IFS='|' read -r tier tag _; do
    [[ "$tier" =~ ^#|^$|^retired$ ]] && continue
    tag="$(echo "$tag" | xargs)"
    echo
    echo "===== [LLM: $tier] ====="
    case "$tier" in
      embed)  test_embed_one "$tag" "$PROMPT" || fail=1 ;;
      rerank) test_rerank_one "$tag" || fail=1 ;;
      *)      test_one "$tag" "$PROMPT" 0 || fail=1 ;;
    esac
  done < "$MANIFEST"
  return "$fail"
}

run_all_image() {
  local fail=0 role id _
  while IFS='|' read -r role id _; do
    [[ "$role" =~ ^#|^$|^retired$ ]] && continue
    echo
    echo "===== [image: $role] ====="
    test_image_one "$id" || fail=1
  done < "$IMG_MANIFEST"
  return "$fail"
}

case "$MODEL" in
  all)
    FAIL=0
    run_all_llm   || FAIL=1
    run_all_image || FAIL=1
    echo; echo "===== [asr] ====="
    test_asr_one  || FAIL=1
    echo; echo "===== [tts] ====="
    test_tts_one  || FAIL=1
    echo
    if [[ "$FAIL" -eq 0 ]]; then echo "ALL MODELS PASSED (LLM + image + asr + tts)"; else echo "SOME MODELS FAILED"; exit 1; fi
    exit 0 ;;
  all-llm)
    run_all_llm && { echo; echo "ALL LLM TIERS PASSED"; } || { echo; echo "SOME LLM TIERS FAILED"; exit 1; }
    exit 0 ;;
  all-image)
    run_all_image && { echo; echo "ALL IMAGE MODELS PASSED"; } || { echo; echo "SOME IMAGE MODELS FAILED"; exit 1; }
    exit 0 ;;
  asr)
    test_asr_one; exit $? ;;
  tts)
    test_tts_one; exit $? ;;
esac

## Role name -> manifest tag (known-but-removed tiers fail with guidance)
ROLE=""
if grep -qE "^$MODEL\|" "$MANIFEST" 2>/dev/null; then
  ROLE="$MODEL"
fi
MODEL="$(resolve_llm_tag "$MODEL" "$MANIFEST")" || exit 1

case "$ROLE" in
  embed)  test_embed_one "$MODEL" "$PROMPT" ;;
  rerank) test_rerank_one "$MODEL" ;;
  *)
    if [[ "$MODEL" == *embedding* ]]; then
      test_embed_one "$MODEL" "$PROMPT"
    else
      test_one "$MODEL" "$PROMPT"
    fi
    ;;
esac
