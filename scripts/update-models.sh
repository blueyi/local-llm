#!/usr/bin/env bash
# =============================================================
# update-models.sh — hardware-aware tier recommendation + update
# =============================================================
# Discovers latest eligible tags from ollama.com, scores them against
# local hardware (+ optional overrides), proposes main/deep/fast changes,
# asks for confirmation, then updates config/models.manifest and deploys.
#
# Usage:
#   lm update                     # auto-detect hardware, propose, confirm, deploy
#   lm update --dry-run           # show proposal only
#   lm update --yes               # skip confirmation (still prints plan)
#   lm update --no-deploy         # write manifest only
#   lm update --ram 48 --chip "Apple M5 Max"
#   lm update --manifest-only     # alias of --no-deploy
#
# Policy: config/update-policy.conf  |  Install SSOT: config/models.manifest
# =============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/common.sh"
CATALOG="$ROOT/scripts/lib/model_catalog.py"
MANIFEST="$ROOT/config/models.manifest"
POLICY="$ROOT/config/update-policy.conf"
CHANGELOG="$ROOT/docs/changelog.md"

DRY_RUN=0
ASSUME_YES=0
DO_DEPLOY=1
RAM=""
CHIP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --no-deploy|--manifest-only) DO_DEPLOY=0; shift ;;
    --ram) RAM="${2:-}"; shift 2 ;;
    --ram=*) RAM="${1#--ram=}"; shift ;;
    --chip) CHIP="${2:-}"; shift 2 ;;
    --chip=*) CHIP="${1#--chip=}"; shift ;;
    -h|--help) grep -E '^#( |=)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1 (see --help)"; exit 1 ;;
  esac
done

command -v python3 >/dev/null 2>&1 || { err "python3 required"; exit 1; }
[[ -f "$CATALOG" ]] || { err "missing $CATALOG"; exit 1; }

REC_ARGS=(--policy "$POLICY" --manifest "$MANIFEST" recommend)
[[ -n "$RAM" ]] && REC_ARGS+=(--ram "$RAM")
[[ -n "$CHIP" ]] && REC_ARGS+=(--chip "$CHIP")

log "Fetching remote catalog + scoring against hardware..."
JSON="$(python3 "$CATALOG" "${REC_ARGS[@]}")" || { err "recommendation failed"; exit 1; }

python3 - "$JSON" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
hw = data["hardware"]
print()
print(
    f"Hardware: {hw['chip']} / {hw['mem_gb']}GB RAM "
    f"(reserve {hw['reserve_gb']}GB → usable ~{hw['usable_gb']}GB, source={hw['source']})"
)
print()
print(f"{'TIER':<6} {'CURRENT':<36} {'PROPOSED':<36} {'SIZE':>6}  NOTE")
print("-" * 110)
for tier in ("main", "deep", "fast"):
    p = data["recommendations"][tier]
    cur = data["current"].get(tier, "") or "-"
    prop = p.get("full") or "-"
    size = p.get("size_gb")
    size_s = f"{size:.1f}G" if isinstance(size, (int, float)) else "?"
    mark = "CHANGE" if p.get("changed") else "same"
    win = p.get("window") or [0, 0]
    note = f"{mark}; window {win[0]}-{win[1]}GB"
    if p.get("family_badges"):
        note += " [" + ",".join(p["family_badges"][:4]) + "]"
    print(f"{tier:<6} {cur:<36} {prop:<36} {size_s:>6}  {note}")
    alts = p.get("alternatives") or []
    if alts and p.get("changed"):
        alt_s = ", ".join(f"{a['full']}({a['size_gb']}G)" for a in alts[:3])
        print(f"       alternatives: {alt_s}")
print()
if not data.get("any_changed"):
    print("No changes recommended — lineup already matches policy + hardware.")
else:
    print(
        "Proposed updates will rewrite config/models.manifest "
        "(HF fallback URLs cleared on change)."
    )
PY

ANY_CHANGED="$(python3 -c 'import json,sys; print(1 if json.loads(sys.argv[1]).get("any_changed") else 0)' "$JSON")"

if [[ "$ANY_CHANGED" -eq 0 ]]; then
  ok "Nothing to update"
  exit 0
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  warn "Dry-run only — manifest not modified"
  exit 0
fi

if [[ "$ASSUME_YES" -eq 0 ]]; then
  echo
  read -r -p "Apply the proposed tier updates? [y/N] " ans
  [[ "$ans" =~ ^[yY]$ ]] || { warn "Cancelled"; exit 0; }
fi

UPDATES_JSON="$(python3 -c '
import json,sys
data=json.loads(sys.argv[1])
print(json.dumps({t: data["recommendations"][t]["full"]
                  for t in ("main","deep","fast")
                  if data["recommendations"][t].get("changed")
                     and data["recommendations"][t].get("full")}))
' "$JSON")"

log "Updating models.manifest"
APPLY="$(python3 "$CATALOG" --policy "$POLICY" --manifest "$MANIFEST" apply-manifest "$UPDATES_JSON")"
python3 -c 'import json,sys; d=json.load(sys.stdin); print("\n".join("  - "+c for c in d.get("changes") or []) or "  (no textual changes)")' <<<"$APPLY"

TODAY="$(date +%Y-%m-%d)"
CHANGES_TXT="$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print("; ".join(d.get("changes") or []))' "$APPLY")"
if [[ -n "$CHANGES_TXT" && -f "$CHANGELOG" ]]; then
  TMP="$(mktemp)"
  {
    echo "# Changelog"
    echo
    echo "## ${TODAY} (lm update: tier refresh)"
    echo
    echo "- \`lm update\` applied: ${CHANGES_TXT}"
    echo "- Install SSOT: \`config/models.manifest\`; policy: \`config/update-policy.conf\`"
    echo
    tail -n +2 "$CHANGELOG"
  } > "$TMP"
  mv "$TMP" "$CHANGELOG"
  ok "Appended docs/changelog.md"
fi

python3 - "$ROOT/docs/tiers.md" "$JSON" <<'PY' || true
import json, re, sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(sys.argv[2])
if not path.is_file():
    raise SystemExit(0)
text = path.read_text(encoding="utf-8")
for tier in ("main", "deep", "fast"):
    rec = data["recommendations"][tier]
    if not rec.get("changed") or not rec.get("full"):
        continue
    new = rec["full"]
    pattern = rf"(\|\s*\*\*{tier}\*\*[^\n]*\|\s*`)([^`]+)(`)"
    text2, n = re.subn(pattern, rf"\g<1>{new}\g<3>", text, count=1)
    if n:
        text = text2
path.write_text(text, encoding="utf-8")
PY

if [[ "$DO_DEPLOY" -eq 1 ]]; then
  log "Deploying updated tiers (ollama pull)..."
  "$ROOT/scripts/deploy.sh" || { err "deploy failed — manifest already updated"; exit 1; }
else
  warn "Skipped deploy — run: lm deploy"
  "$ROOT/scripts/sync-registry.sh" || true
fi

ok "Update complete"
