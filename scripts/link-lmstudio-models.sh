#!/usr/bin/env bash
# Symlink GGUFs into LM Studio models folder for easy discovery.
set -euo pipefail
SRC="${1:-$HOME/models/gguf}"
# Common LM Studio model roots
CANDIDATES=(
  "$HOME/.lmstudio/models"
  "$HOME/.cache/lm-studio/models"
  "$HOME/Library/Application Support/LM Studio/models"
)
DEST=""
for d in "${CANDIDATES[@]}"; do
  if [[ -d "$d" ]]; then DEST="$d"; break; fi
done
if [[ -z "$DEST" ]]; then
  DEST="$HOME/.lmstudio/models"
  mkdir -p "$DEST"
  echo "Created $DEST"
fi

if [[ ! -d "$SRC" ]]; then
  echo "Source not found: $SRC"
  exit 1
fi

TARGET="$DEST/llm-gguf"
mkdir -p "$(dirname "$TARGET")"
ln -sfn "$SRC" "$TARGET"
echo "Linked: $TARGET -> $SRC"
echo "Open LM Studio → My Models; refresh if needed."
ls -la "$TARGET" | head -30
