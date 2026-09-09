#!/usr/bin/env bash
# =============================================================
# deps.sh — software dependency check + optional auto-install
# =============================================================
# Sourced library (like common.sh); callers own set -euo pipefail and ROOT.
# Used by init-models.sh (phase 0, before probing) so a fresh machine gets
# its engines installed before manifests are written / deployed.
#
# Engine/tool-level deps only — model names never appear here
# (install SSOT remains config/*.manifest).
#
# Stack → deps:
#   llm   : ollama      → scripts/upgrade-ollama.sh --upgrade (upstream tgz)
#   image : mflux       → uv tool install mflux
#                         (checks GEN_CLI/EDIT_CLI from image-models.manifest)
#   asr   : mlx-whisper → uv tool install mlx-whisper
#   tts   : mlx-audio   → uv tool install mlx-audio --with misaki[en,zh]
#           espeak-ng   → brew install espeak-ng (Kokoro English phonemes)
#
# API:
#   deps_ensure STACK [STACK...]
#   ensure_weights_root           # ~/models/* + ~/.ollama/models symlink
# Flags (env): DEPS_ASSUME_YES=1 (no prompt), DEPS_DRY_RUN=1 (report only)
# Returns 0 when everything is present / installed / skipped-by-user;
# returns 1 when an install was attempted and failed.
# =============================================================

# Stack -> space-separated dep names
_deps_for_stack() {
  case "$1" in
    llm)          echo "ollama" ;;
    image)        echo "mflux" ;;
    asr|speech)   echo "mlx-whisper" ;;
    tts)          echo "mlx-audio espeak-ng" ;;
    *)            echo "" ;;
  esac
}

_dep_present() {
  local name="$1"
  case "$name" in
    ollama)
      command -v ollama >/dev/null 2>&1 && return 0
      # daemon may be answering even when the binary is not on PATH
      curl -s -m 2 -o /dev/null "http://127.0.0.1:11434/api/tags" 2>/dev/null
      ;;
    mflux)
      # every GEN_CLI / EDIT_CLI referenced by active image rows must exist
      local cli missing=0
      while IFS= read -r cli; do
        [[ -n "$cli" ]] || continue
        command -v "$cli" >/dev/null 2>&1 || { missing=1; break; }
      done < <(awk -F'|' '$1=="primary"||$1=="alt"{print $4; if($5!="")print $5}' \
                 "$ROOT/config/image-models.manifest" 2>/dev/null)
      [[ "$missing" -eq 0 ]]
      ;;
    mlx-whisper)  command -v mlx_whisper >/dev/null 2>&1 ;;
    mlx-audio)    command -v mlx_audio.tts.generate >/dev/null 2>&1 ;;
    espeak-ng)    command -v espeak-ng >/dev/null 2>&1 ;;
    *)            return 1 ;;
  esac
}

_uv_tool_install() {
  command -v uv >/dev/null 2>&1 || { err "uv not installed — run: brew install uv"; return 1; }
  uv tool install "$@"
}

_dep_install() {
  local name="$1"
  case "$name" in
    ollama)
      "$ROOT/scripts/upgrade-ollama.sh" --upgrade
      ;;
    mflux)
      _uv_tool_install mflux
      ;;
    mlx-whisper)
      _uv_tool_install mlx-whisper
      ;;
    mlx-audio)
      _uv_tool_install mlx-audio --with 'misaki[en]' --with 'misaki[zh]' || return 1
      warn "Kokoro English also needs espeak-ng + spaCy en_core_web_sm in the tool env — see docs/operations.md (语音 TTS)"
      ;;
    espeak-ng)
      command -v brew >/dev/null 2>&1 || { warn "brew not installed — skip espeak-ng"; return 1; }
      brew install espeak-ng
      ;;
    *)
      err "no installer for dep: $name"
      return 1
      ;;
  esac
}

# Weights root bootstrap (path convention: ~/models/, see AGENTS.md).
# Idempotent: creates ~/models/{ollama,gguf,image-gen,speech,tts} and the
# ~/.ollama/models -> ~/models/ollama symlink. If a real (non-symlink)
# ~/.ollama/models dir already holds data, we do NOT auto-migrate (the
# daemon may be mid-pull) — warn with manual steps instead.
ensure_weights_root() {
  local root="${LLM_MODELS_ROOT:-$HOME/models}"
  mkdir -p "$root/ollama" "$root/gguf" "$root/image-gen" "$root/speech" "$root/tts" || {
    warn "could not create weights root under $root"
    return 1
  }
  local link="$HOME/.ollama/models"
  if [[ -L "$link" ]]; then
    return 0
  elif [[ -d "$link" ]]; then
    if [[ -z "$(ls -A "$link" 2>/dev/null)" ]]; then
      rmdir "$link" && ln -sfn "$root/ollama" "$link"
    else
      warn "~/.ollama/models is a real directory with data — migrate manually:"
      warn "  rsync -a ~/.ollama/models/ ~/models/ollama/ && rm -rf ~/.ollama/models && ln -sfn ~/models/ollama ~/.ollama/models"
      return 1
    fi
  else
    mkdir -p "$HOME/.ollama" && ln -sfn "$root/ollama" "$link"
  fi
  ok "weights root: $root (ollama symlinked)"
  return 0
}

deps_ensure() {
  local stacks=("$@") deps=() d s
  for s in ${stacks[@]+"${stacks[@]}"}; do
    for d in $(_deps_for_stack "$s"); do
      [[ -n "$d" ]] || continue
      case " ${deps[*]:-} " in
        *" $d "*) ;;                 # already queued
        *) deps+=("$d") ;;
      esac
    done
  done
  [[ "${#deps[@]}" -eq 0 ]] && return 0

  log "Checking software dependencies..."
  local missing=()
  for d in "${deps[@]}"; do
    if _dep_present "$d"; then
      ok "$d"
    else
      warn "missing: $d"
      missing+=("$d")
    fi
  done
  [[ "${#missing[@]}" -eq 0 ]] && return 0

  if [[ "${DEPS_DRY_RUN:-0}" -eq 1 ]]; then
    warn "dry-run — not installing: ${missing[*]}"
    return 0
  fi

  local do_install=0 ans
  if [[ "${DEPS_ASSUME_YES:-0}" -eq 1 ]]; then
    do_install=1
  elif [[ -t 0 ]]; then
    read -r -p "Install missing dependencies now? (${missing[*]}) [Y/n] " ans
    ans="${ans:-Y}"
    [[ "$ans" =~ ^[yY]$ ]] && do_install=1
  else
    warn "non-interactive stdin — skipping auto-install (use --yes to install: ${missing[*]})"
  fi

  if [[ "$do_install" -ne 1 ]]; then
    warn "Skipped dependency install — still missing: ${missing[*]}"
    return 0
  fi

  local failed=()
  for d in "${missing[@]}"; do
    log "Installing $d ..."
    if _dep_install "$d"; then
      ok "$d installed"
    else
      err "install failed: $d"
      failed+=("$d")
    fi
  done
  hash -r 2>/dev/null || true
  if [[ "${#failed[@]}" -gt 0 ]]; then
    warn "failed to install: ${failed[*]} — affected stacks will fail at deploy/pull time"
    return 1
  fi
  ok "All dependencies satisfied"
  return 0
}
