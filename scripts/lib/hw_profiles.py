#!/usr/bin/env python3
"""Hardware probe + exact Mac profile matching for `lm init`.

Stdlib only. Does not change `model_catalog.detect_hardware` (used by `lm update`).
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

LIB = Path(__file__).resolve().parent
if str(LIB) not in sys.path:
    sys.path.insert(0, str(LIB))

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PROFILES = ROOT / "config" / "hardware-profiles.tsv"
DEFAULT_LINEUPS = ROOT / "config" / "lineups.tsv"
DEFAULT_INIT_POLICY = ROOT / "config" / "init-policy.conf"
DEFAULT_UPDATE_POLICY = ROOT / "config" / "update-policy.conf"
DEFAULT_LLM_MANIFEST = ROOT / "config" / "models.manifest"
DEFAULT_IMAGE_MANIFEST = ROOT / "config" / "image-models.manifest"
DEFAULT_ASR_MANIFEST = ROOT / "config" / "speech-models.manifest"
DEFAULT_TTS_MANIFEST = ROOT / "config" / "tts-models.manifest"

MEM_BUCKETS = (8, 16, 18, 24, 32, 36, 48, 64, 96, 128, 192)
LLM_ROLES = ("main", "deep", "fast", "embed", "chat", "reason", "rerank")
IMAGE_ROLES = ("primary", "alt")
ASR_ROLES = ("primary", "alt")
TTS_ROLES = ("primary", "alt")
ALL_STACKS = ("llm", "image", "asr", "tts")

CHIP_RE = re.compile(
    r"(?:Apple\s+)?M(\d)\s*(Pro|Max|Ultra)?\b",
    re.I,
)


# ---------------------------------------------------------------------------
# Small conf / TSV helpers
# ---------------------------------------------------------------------------


def load_kv_conf(path: Path) -> dict[str, str]:
    policy: dict[str, str] = {}
    if not path.is_file():
        return policy
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        policy[k.strip()] = v.strip()
    return policy


def _csv(policy: dict[str, str], key: str, default: str = "") -> list[str]:
    raw = policy.get(key, default)
    return [x.strip() for x in raw.split(",") if x.strip()]


def _f(policy: dict[str, str], key: str, default: float) -> float:
    try:
        return float(policy.get(key, default))
    except ValueError:
        return default


def _i(policy: dict[str, str], key: str, default: int) -> int:
    try:
        return int(float(policy.get(key, default)))
    except ValueError:
        return default


def _iter_tsv(path: Path) -> list[list[str]]:
    rows: list[list[str]] = []
    if not path.is_file():
        return rows
    for line in path.read_text(encoding="utf-8").splitlines():
        raw = line.strip()
        if not raw or raw.startswith("#"):
            continue
        rows.append(line.split("|"))
    return rows


# ---------------------------------------------------------------------------
# Chip / RAM / probe
# ---------------------------------------------------------------------------


def parse_chip(chip: str) -> tuple[str, str]:
    """Return (family, variant) e.g. ('m5', 'max'). Empty strings if unknown."""
    if not chip:
        return "", ""
    m = CHIP_RE.search(chip.strip())
    if not m:
        return "", ""
    family = f"m{m.group(1)}"
    variant = (m.group(2) or "base").lower()
    return family, variant


def quantize_ram_gb(mem_gb: float, max_delta: float = 2.0) -> int:
    """Snap to a known Apple unified-memory bucket when close enough."""
    if mem_gb <= 0:
        return 0
    best = min(MEM_BUCKETS, key=lambda b: abs(b - mem_gb))
    if abs(best - mem_gb) <= max_delta:
        return int(best)
    return int(round(mem_gb))


def _run(cmd: list[str], timeout: float = 12.0) -> str:
    try:
        return subprocess.check_output(
            cmd, text=True, timeout=timeout, stderr=subprocess.DEVNULL
        ).strip()
    except Exception:  # noqa: BLE001 — best-effort probe
        return ""


def _parse_hw_profiler(text: str) -> tuple[str, str]:
    model_id = ""
    chip = ""
    for line in text.splitlines():
        if ":" not in line:
            continue
        key, val = line.split(":", 1)
        key, val = key.strip(), val.strip()
        if key == "Model Identifier":
            model_id = val
        elif key == "Chip":
            chip = val
    return model_id, chip


def _parse_gpu_cores(text: str) -> int | None:
    # ioreg: "gpu-core-count" = 40
    m = re.search(r'"gpu-core-count"\s*=\s*(\d+)', text)
    if m:
        return int(m.group(1))
    m = re.search(r"Total Number of Cores:\s*(\d+)", text)
    if m:
        return int(m.group(1))
    return None


@dataclass
class MachineProbe:
    mem_gb: float
    mem_bucket: int
    chip: str
    family: str
    variant: str
    model_id: str = ""
    gpu_cores: int | None = None
    source: str = "auto"  # auto | override | default

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def probe_machine(
    ram_gb: float | None = None,
    chip: str | None = None,
) -> MachineProbe:
    """Probe this Mac (or Linux best-effort). Overrides skip sysctl for that field."""
    import platform

    source = "override" if ram_gb is not None else "auto"
    detected_mem = ram_gb
    detected_chip = chip or ""
    model_id = ""
    gpu_cores: int | None = None
    system = platform.system()

    if system == "Darwin":
        if detected_mem is None:
            out = _run(["sysctl", "-n", "hw.memsize"], timeout=5)
            if out.isdigit():
                detected_mem = int(out) / (1024**3)
        if not detected_chip:
            detected_chip = _run(["sysctl", "-n", "machdep.cpu.brand_string"], timeout=5)
        # Extra fields; skip profiler when both ram+chip were overridden (tests / CI)
        if ram_gb is None or chip is None:
            hw_txt = _run(["system_profiler", "SPHardwareDataType"], timeout=20)
            mid, chip_from_sp = _parse_hw_profiler(hw_txt)
            model_id = mid
            if not detected_chip and chip_from_sp:
                detected_chip = chip_from_sp
            ioreg = _run(
                ["ioreg", "-r", "-d", "1", "-c", "AGXAccelerator"], timeout=8
            )
            gpu_cores = _parse_gpu_cores(ioreg)
            if gpu_cores is None:
                disp = _run(["system_profiler", "SPDisplaysDataType"], timeout=20)
                gpu_cores = _parse_gpu_cores(disp)
    elif system == "Linux":
        if detected_mem is None:
            try:
                with open("/proc/meminfo", encoding="utf-8") as fh:
                    for line in fh:
                        if line.startswith("MemTotal:"):
                            detected_mem = int(line.split()[1]) / (1024**2)
                            break
            except OSError:
                pass
        if not detected_chip:
            try:
                with open("/proc/cpuinfo", encoding="utf-8") as fh:
                    for line in fh:
                        if line.startswith("model name"):
                            detected_chip = line.split(":", 1)[1].strip()
                            break
            except OSError:
                pass

    if detected_mem is None:
        detected_mem = 48.0
        source = "default"
        print(
            "warn: could not detect RAM; defaulting to 48GB (pass --ram)",
            file=sys.stderr,
        )
    if not detected_chip:
        detected_chip = "unknown"

    family, variant = parse_chip(detected_chip)
    bucket = quantize_ram_gb(float(detected_mem))
    return MachineProbe(
        mem_gb=round(float(detected_mem), 1),
        mem_bucket=bucket,
        chip=detected_chip,
        family=family,
        variant=variant,
        model_id=model_id,
        gpu_cores=gpu_cores,
        source=source,
    )


# ---------------------------------------------------------------------------
# Profiles + lineups
# ---------------------------------------------------------------------------


@dataclass
class HwProfile:
    id: str
    family: str
    variant: str
    mem_gb: int
    chip_regex: str
    gpu_cores: int | None
    lineup: str

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def load_profiles(path: Path = DEFAULT_PROFILES) -> list[HwProfile]:
    out: list[HwProfile] = []
    for parts in _iter_tsv(path):
        if len(parts) < 7:
            continue
        gpu_raw = parts[5].strip()
        gpu: int | None
        try:
            gpu = int(gpu_raw) if gpu_raw else None
        except ValueError:
            gpu = None
        out.append(
            HwProfile(
                id=parts[0].strip(),
                family=parts[1].strip().lower(),
                variant=parts[2].strip().lower(),
                mem_gb=int(float(parts[3])),
                chip_regex=parts[4].strip(),
                gpu_cores=gpu,
                lineup=parts[6].strip(),
            )
        )
    return out


def match_profile(
    probe: MachineProbe, profiles: list[HwProfile] | None = None
) -> HwProfile | None:
    """Exact (family, variant, mem_bucket) match. No nearest-RAM fallback."""
    profiles = profiles if profiles is not None else load_profiles()
    hits: list[HwProfile] = []
    for p in profiles:
        if p.family != probe.family or p.variant != probe.variant:
            continue
        if p.mem_gb != probe.mem_bucket:
            continue
        if p.chip_regex and not re.search(p.chip_regex, probe.chip):
            continue
        if (
            p.gpu_cores is not None
            and probe.gpu_cores is not None
            and p.gpu_cores != probe.gpu_cores
        ):
            continue
        hits.append(p)
    if not hits:
        return None
    return hits[0]


@dataclass
class LineupRow:
    lineup: str
    stack: str
    role: str
    model: str
    extra: list[str] = field(default_factory=list)


def load_lineups(path: Path = DEFAULT_LINEUPS) -> list[LineupRow]:
    rows: list[LineupRow] = []
    for parts in _iter_tsv(path):
        if len(parts) < 4:
            continue
        rows.append(
            LineupRow(
                lineup=parts[0].strip(),
                stack=parts[1].strip(),
                role=parts[2].strip(),
                model=parts[3].strip(),
                extra=[p for p in parts[4:]],
            )
        )
    return rows


def lineup_rows_for(lineup: str, path: Path = DEFAULT_LINEUPS) -> list[LineupRow]:
    return [r for r in load_lineups(path) if r.lineup == lineup]


def ram_band_lineup(mem_bucket: int, policy: dict[str, str] | None = None) -> str:
    policy = policy if policy is not None else load_kv_conf(DEFAULT_INIT_POLICY)
    mapping: dict[int, str] = {}
    for item in _csv(policy, "RAM_BAND_LINEUPS"):
        if ":" not in item:
            continue
        k, v = item.split(":", 1)
        try:
            mapping[int(k)] = v.strip()
        except ValueError:
            continue
    if mem_bucket in mapping:
        return mapping[mem_bucket]
    # nearest *lower* known band (never round up into a bigger lineup)
    lower = [b for b in sorted(mapping) if b <= mem_bucket]
    if lower:
        return mapping[lower[-1]]
    return mapping.get(16, "lite-16")


# ---------------------------------------------------------------------------
# Stack dicts (proposed / current)
# ---------------------------------------------------------------------------


def llm_spec_from_row(row: LineupRow) -> dict[str, str]:
    extra = list(row.extra) + ["", "", ""]
    return {
        "model": row.model,
        "num_ctx": extra[0],
        "hf_gguf": extra[1],
        "mmproj": extra[2],
    }


def image_spec_from_row(row: LineupRow) -> dict[str, str]:
    extra = list(row.extra) + ["", "", "", ""]
    return {
        "model": row.model,
        "hf_repo": extra[0],
        "gen_cli": extra[1],
        "edit_cli": extra[2],
        "base_model_arg": extra[3],
        "steps": extra[4],
    }


def asr_spec_from_row(row: LineupRow) -> dict[str, str]:
    extra = list(row.extra) + ["", ""]
    return {
        "model": row.model,
        "hf_repo": extra[0],
        "engine": extra[1] or "mlx-whisper",
    }


def tts_spec_from_row(row: LineupRow) -> dict[str, str]:
    extra = list(row.extra) + ["", "", ""]
    return {
        "model": row.model,
        "hf_repo": extra[0],
        "engine": extra[1] or "mlx-audio",
        "default_voice": extra[2],
    }


def stacks_from_lineup(lineup: str) -> dict[str, dict[str, dict[str, str]]]:
    stacks: dict[str, dict[str, dict[str, str]]] = {
        "llm": {},
        "image": {},
        "asr": {},
        "tts": {},
    }
    for row in lineup_rows_for(lineup):
        if row.stack == "llm":
            stacks["llm"][row.role] = llm_spec_from_row(row)
        elif row.stack == "image":
            stacks["image"][row.role] = image_spec_from_row(row)
        elif row.stack == "asr":
            stacks["asr"][row.role] = asr_spec_from_row(row)
        elif row.stack == "tts":
            stacks["tts"][row.role] = tts_spec_from_row(row)
    return stacks


def parse_pipe_manifest(
    path: Path, roles: tuple[str, ...]
) -> dict[str, list[str]]:
    """role -> raw field list (including role as [0])."""
    found: dict[str, list[str]] = {}
    if not path.is_file():
        return found
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#") or "|" not in line:
            continue
        parts = line.split("|")
        role = parts[0].strip()
        if role in roles:
            found[role] = parts
    return found


def current_llm_stack(path: Path = DEFAULT_LLM_MANIFEST) -> dict[str, dict[str, str]]:
    out: dict[str, dict[str, str]] = {}
    for role, parts in parse_pipe_manifest(path, LLM_ROLES).items():
        while len(parts) < 5:
            parts.append("")
        out[role] = {
            "model": parts[1].strip(),
            "num_ctx": parts[2].strip(),
            "hf_gguf": parts[3].strip(),
            "mmproj": parts[4].strip(),
        }
    return out


def current_image_stack(
    path: Path = DEFAULT_IMAGE_MANIFEST,
) -> dict[str, dict[str, str]]:
    out: dict[str, dict[str, str]] = {}
    for role, parts in parse_pipe_manifest(path, IMAGE_ROLES).items():
        while len(parts) < 7:
            parts.append("")
        out[role] = {
            "model": parts[1].strip(),
            "hf_repo": parts[2].strip(),
            "gen_cli": parts[3].strip(),
            "edit_cli": parts[4].strip(),
            "base_model_arg": parts[5].strip(),
            "steps": parts[6].strip(),
        }
    return out


def current_asr_stack(path: Path = DEFAULT_ASR_MANIFEST) -> dict[str, dict[str, str]]:
    out: dict[str, dict[str, str]] = {}
    for role, parts in parse_pipe_manifest(path, ASR_ROLES).items():
        while len(parts) < 4:
            parts.append("")
        out[role] = {
            "model": parts[1].strip(),
            "hf_repo": parts[2].strip(),
            "engine": parts[3].strip(),
        }
    return out


def current_tts_stack(path: Path = DEFAULT_TTS_MANIFEST) -> dict[str, dict[str, str]]:
    out: dict[str, dict[str, str]] = {}
    for role, parts in parse_pipe_manifest(path, TTS_ROLES).items():
        while len(parts) < 5:
            parts.append("")
        out[role] = {
            "model": parts[1].strip(),
            "hf_repo": parts[2].strip(),
            "engine": parts[3].strip(),
            "default_voice": parts[4].strip(),
        }
    return out


def current_stacks() -> dict[str, dict[str, dict[str, str]]]:
    return {
        "llm": current_llm_stack(),
        "image": current_image_stack(),
        "asr": current_asr_stack(),
        "tts": current_tts_stack(),
    }


def _spec_eq(a: dict[str, str], b: dict[str, str]) -> bool:
    keys = set(a) | set(b)
    return all((a.get(k) or "") == (b.get(k) or "") for k in keys)


def diff_stacks(
    current: dict[str, dict[str, dict[str, str]]],
    proposed: dict[str, dict[str, dict[str, str]]],
    stacks: list[str],
) -> list[str]:
    changes: list[str] = []
    for stack in stacks:
        cur = current.get(stack) or {}
        prop = proposed.get(stack) or {}
        roles = []
        if stack == "llm":
            roles = list(LLM_ROLES)
        elif stack == "image":
            roles = list(IMAGE_ROLES)
        else:
            roles = list(ASR_ROLES)
        seen = set(cur) | set(prop)
        ordered = [r for r in roles if r in seen] + [
            r for r in seen if r not in roles
        ]
        for role in ordered:
            if role in prop and role not in cur:
                changes.append(f"{stack}.{role}: (none) -> {prop[role]['model']}")
            elif role in cur and role not in prop:
                changes.append(f"{stack}.{role}: {cur[role]['model']} -> (removed)")
            elif role in cur and role in prop and not _spec_eq(cur[role], prop[role]):
                changes.append(
                    f"{stack}.{role}: {cur[role].get('model', '')} -> {prop[role]['model']}"
                )
    return changes


# ---------------------------------------------------------------------------
# Fallback scoring (does not modify model_catalog scoring used by lm update)
# ---------------------------------------------------------------------------


def scaled_init_policy(
    mem_gb: float, path: Path = DEFAULT_INIT_POLICY
) -> dict[str, str]:
    policy = load_kv_conf(path)
    if mem_gb <= 16:
        policy["RESERVE_GB"] = policy.get("RESERVE_GB_16", "6")
    elif mem_gb <= 24:
        policy["RESERVE_GB"] = policy.get("RESERVE_GB_24", "8")
    else:
        policy.setdefault("RESERVE_GB", "12")

    if policy.get("SCALE_ABS_WITH_RAM", "1") != "1":
        return policy

    reserve = _f(policy, "RESERVE_GB", 12.0)
    usable = max(4.0, float(mem_gb) - reserve)
    for prefix, frac_default, ceil_default in (
        ("MAIN", 0.72, 80.0),
        ("DEEP", 0.95, 90.0),
        ("FAST", 0.28, 10.0),
        ("EMBED", 0.25, 8.0),
        ("CHAT", 0.70, 36.0),
        ("REASON", 0.70, 80.0),
        ("RERANK", 0.20, 6.0),
    ):
        frac = _f(policy, f"{prefix}_FRAC_MAX", frac_default)
        cap = usable * frac
        ceil = _f(policy, f"{prefix}_ABS_CEIL", ceil_default)
        policy[f"{prefix}_ABS_MAX"] = str(round(min(cap, ceil, usable), 1))
    return policy


def _llm_from_picks(
    picks: dict[str, dict],
    policy: dict[str, str],
    extras: dict[str, dict[str, str]],
) -> dict[str, dict[str, str]]:
    out: dict[str, dict[str, str]] = {}
    ctx = {
        "main": str(_i(policy, "MAIN_NUM_CTX", 65536)),
        "deep": str(_i(policy, "DEEP_NUM_CTX", 32768)),
        "fast": str(_i(policy, "FAST_NUM_CTX", 32768)),
        "embed": str(_i(policy, "EMBED_NUM_CTX", 8192)),
        "chat": str(_i(policy, "CHAT_NUM_CTX", 65536)),
        "reason": str(_i(policy, "REASON_NUM_CTX", 65536)),
        "rerank": str(_i(policy, "RERANK_NUM_CTX", 8192)),
    }
    for role, rec in picks.items():
        tag = (rec.get("full") or "").strip()
        if not tag:
            continue
        out[role] = {
            "model": tag,
            "num_ctx": ctx.get(role, "32768"),
            "hf_gguf": "",
            "mmproj": "",
        }
    for role, spec in extras.items():
        if spec.get("model"):
            out[role] = spec
    return out


def _pick_support_role(
    role: str,
    families: list[str],
    hw: Any,
    policy: dict[str, str],
    used_full: set[str],
) -> dict[str, str] | None:
    import model_catalog as mc

    base = policy.get("OLLAMA_LIBRARY_BASE", "https://ollama.com")
    registry = policy.get("OLLAMA_REGISTRY_BASE", "https://registry.ollama.ai")
    exclude = _csv(policy, "EXCLUDE_TAG_SUBSTR")
    fam_weight = _f(policy, "FAMILY_PRIORITY_WEIGHT", 12.0)
    lo, hi = mc.tier_window(role, hw, policy)
    ranked: list[tuple[float, Any]] = []
    for pri, name in enumerate(families):
        try:
            tags = mc.fetch_tags(name, base, registry)
        except Exception as exc:  # noqa: BLE001
            print(f"warn: skip family {name}: {exc}", file=sys.stderr)
            continue
        for tag in tags:
            if tag.full in used_full:
                continue
            if mc._excluded(tag.tag, exclude) or mc._excluded(tag.full, exclude):
                continue
            if tag.size_gb < lo * 0.85 or tag.size_gb > hi * 1.02:
                continue
            score = 100.0 - abs(tag.size_gb - (lo + hi) / 2) * 1.5 - pri * fam_weight
            ranked.append((score, tag))
    if not ranked:
        return None
    ranked.sort(key=lambda x: x[0], reverse=True)
    best = ranked[0][1]
    ctx_key = f"{role.upper()}_NUM_CTX"
    return {
        "model": best.full,
        "num_ctx": str(_i(policy, ctx_key, 8192)),
        "hf_gguf": "",
        "mmproj": "",
    }


def fallback_stacks(
    probe: MachineProbe,
    current: dict[str, dict[str, dict[str, str]]],
) -> dict[str, dict[str, dict[str, str]]]:
    """Score main/deep/fast via existing recommend_tiers; heuristics for the rest."""
    import model_catalog as mc

    policy = scaled_init_policy(probe.mem_gb)
    reserve = _f(policy, "RESERVE_GB", 12.0)
    hw = mc.Hardware(
        mem_gb=probe.mem_gb,
        chip=probe.chip,
        reserve_gb=reserve,
        usable_gb=round(max(4.0, probe.mem_gb - reserve), 1),
        source=probe.source,
    )
    cur_llm = current.get("llm") or {}
    current_tags = {role: spec.get("model", "") for role, spec in cur_llm.items()}
    try:
        picks = mc.recommend_tiers(hw, policy, current_tags)
    except Exception as exc:  # noqa: BLE001
        raise RuntimeError(
            f"fallback scoring failed (need network for unmatched SKUs): {exc}"
        ) from exc

    used: set[str] = set()
    extras: dict[str, dict[str, str]] = {}
    for role in ("main", "deep", "fast"):
        full = (picks.get(role) or {}).get("full") or ""
        if full:
            used.add(full)

    role_fams = {
        "embed": _csv(policy, "EMBED_FAMILIES"),
        "chat": _csv(policy, "CHAT_FAMILIES"),
        "reason": _csv(policy, "REASON_FAMILIES"),
        "rerank": _csv(policy, "RERANK_FAMILIES"),
    }
    for role, fams in role_fams.items():
        if not fams:
            continue
        try:
            spec = _pick_support_role(role, fams, hw, policy, used)
        except Exception as exc:  # noqa: BLE001
            print(f"warn: {role} fallback skipped: {exc}", file=sys.stderr)
            spec = None
        if spec and spec.get("model"):
            extras[role] = spec
            used.add(spec["model"])

    llm = _llm_from_picks(picks, policy, extras)
    band = ram_band_lineup(probe.mem_bucket, policy)
    aux = stacks_from_lineup(band)
    return {
        "llm": llm,
        "image": aux.get("image") or {},
        "asr": aux.get("asr") or {},
        "tts": aux.get("tts") or {},
    }


# ---------------------------------------------------------------------------
# Manifest writers (preserve comments + retired lines)
# ---------------------------------------------------------------------------


def _format_llm_line(role: str, spec: dict[str, str]) -> str:
    return "|".join(
        [
            role,
            spec.get("model", ""),
            spec.get("num_ctx", ""),
            spec.get("hf_gguf", ""),
            spec.get("mmproj", ""),
        ]
    )


def _format_image_line(role: str, spec: dict[str, str]) -> str:
    return "|".join(
        [
            role,
            spec.get("model", ""),
            spec.get("hf_repo", ""),
            spec.get("gen_cli", ""),
            spec.get("edit_cli", ""),
            spec.get("base_model_arg", ""),
            spec.get("steps", ""),
        ]
    )


def _format_asr_line(role: str, spec: dict[str, str]) -> str:
    return "|".join(
        [
            role,
            spec.get("model", ""),
            spec.get("hf_repo", ""),
            spec.get("engine", "mlx-whisper"),
        ]
    )


def _format_tts_line(role: str, spec: dict[str, str]) -> str:
    return "|".join(
        [
            role,
            spec.get("model", ""),
            spec.get("hf_repo", ""),
            spec.get("engine", "mlx-audio"),
            spec.get("default_voice", ""),
        ]
    )


def _rewrite_role_lines(
    path: Path,
    proposed: dict[str, dict[str, str]],
    active_roles: tuple[str, ...],
    formatter,
) -> bool:
    """Replace/remove/insert active role lines; keep comments and retired|."""
    if not path.is_file():
        return False
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    new_lines: list[str] = []
    seen: set[str] = set()
    changed = False

    def is_active(raw: str) -> str | None:
        s = raw.strip()
        if not s or s.startswith("#") or "|" not in s:
            return None
        role = s.split("|", 1)[0].strip()
        if role in active_roles:
            return role
        return None

    for line in lines:
        raw = line.rstrip("\n")
        role = is_active(raw)
        if role is None:
            new_lines.append(line)
            continue
        if role in proposed:
            formatted = formatter(role, proposed[role])
            nl = "\n" if line.endswith("\n") else ""
            new_line = formatted + nl
            if new_line != line:
                changed = True
            new_lines.append(new_line)
            seen.add(role)
        else:
            changed = True
            # drop role

    missing = [r for r in active_roles if r in proposed and r not in seen]
    if missing:
        insert_at = None
        for i, line in enumerate(new_lines):
            if line.startswith("retired|"):
                insert_at = i
                break
        block = [formatter(r, proposed[r]) + "\n" for r in missing]
        if insert_at is None:
            if new_lines and not new_lines[-1].endswith("\n"):
                new_lines[-1] += "\n"
            new_lines.extend(block)
        else:
            new_lines[insert_at:insert_at] = block
        changed = True

    if changed:
        path.write_text("".join(new_lines), encoding="utf-8")
    return changed


def apply_stacks(
    proposed: dict[str, dict[str, dict[str, str]]],
    stacks: list[str],
) -> list[str]:
    written: list[str] = []
    if "llm" in stacks:
        if _rewrite_role_lines(
            DEFAULT_LLM_MANIFEST, proposed.get("llm") or {}, LLM_ROLES, _format_llm_line
        ):
            written.append(str(DEFAULT_LLM_MANIFEST.relative_to(ROOT)))
    if "image" in stacks:
        if _rewrite_role_lines(
            DEFAULT_IMAGE_MANIFEST,
            proposed.get("image") or {},
            IMAGE_ROLES,
            _format_image_line,
        ):
            written.append(str(DEFAULT_IMAGE_MANIFEST.relative_to(ROOT)))
    if "asr" in stacks:
        if _rewrite_role_lines(
            DEFAULT_ASR_MANIFEST, proposed.get("asr") or {}, ASR_ROLES, _format_asr_line
        ):
            written.append(str(DEFAULT_ASR_MANIFEST.relative_to(ROOT)))
    if "tts" in stacks:
        if _rewrite_role_lines(
            DEFAULT_TTS_MANIFEST, proposed.get("tts") or {}, TTS_ROLES, _format_tts_line
        ):
            written.append(str(DEFAULT_TTS_MANIFEST.relative_to(ROOT)))
    return written


# ---------------------------------------------------------------------------
# Plan
# ---------------------------------------------------------------------------


def parse_stack_arg(raw: str) -> list[str]:
    if not raw or raw.strip().lower() == "all":
        return list(ALL_STACKS)
    parts = [p.strip().lower() for p in raw.split(",") if p.strip()]
    unknown = [p for p in parts if p not in ALL_STACKS]
    if unknown:
        raise ValueError(f"unknown stack(s): {', '.join(unknown)} (use llm,image,asr,tts,all)")
    # preserve order
    return [s for s in ALL_STACKS if s in parts]


def build_plan(
    ram_gb: float | None = None,
    chip: str | None = None,
    stack_arg: str = "all",
) -> dict[str, Any]:
    stacks = parse_stack_arg(stack_arg)
    probe = probe_machine(ram_gb, chip)
    profiles = load_profiles()
    hit = match_profile(probe, profiles)
    current = current_stacks()
    if hit:
        source = f"profile:{hit.id}"
        proposed = stacks_from_lineup(hit.lineup)
        lineup = hit.lineup
        profile_id = hit.id
    else:
        source = "fallback"
        lineup = ram_band_lineup(probe.mem_bucket)
        profile_id = None
        proposed = fallback_stacks(probe, current)

    changes = diff_stacks(current, proposed, stacks)
    return {
        "hardware": probe.to_dict(),
        "source": source,
        "profile_id": profile_id,
        "lineup": lineup,
        "stacks_requested": stacks,
        "proposed": {s: proposed.get(s) or {} for s in stacks},
        "current": {s: current.get(s) or {} for s in stacks},
        "changes": changes,
        "any_changed": bool(changes),
    }


def format_plan(data: dict[str, Any]) -> str:
    hw = data["hardware"]
    lines: list[str] = [
        "",
        (
            f"Hardware: {hw.get('chip')} / {hw.get('mem_gb')}GB "
            f"(bucket={hw.get('mem_bucket')}GB, "
            f"{hw.get('family') or '?'} {hw.get('variant') or '?'}, "
            f"gpu={hw.get('gpu_cores') or '-'}, "
            f"id={hw.get('model_id') or '-'}, source={hw.get('source')})"
        ),
        f"Source:   {data.get('source')}  lineup={data.get('lineup') or '-'}",
        "",
    ]
    for stack in data.get("stacks_requested") or []:
        prop = (data.get("proposed") or {}).get(stack) or {}
        cur = (data.get("current") or {}).get(stack) or {}
        lines.append(f"[{stack}]")
        roles = list(prop.keys()) or list(cur.keys())
        if stack == "llm":
            roles = [r for r in LLM_ROLES if r in prop or r in cur]
        elif stack == "image":
            roles = [r for r in IMAGE_ROLES if r in prop or r in cur]
        else:
            roles = [r for r in ASR_ROLES if r in prop or r in cur]
        if not roles:
            lines.append("  (empty)")
            continue
        for role in roles:
            p = prop.get(role)
            c = cur.get(role)
            pmodel = p["model"] if p else "(removed)"
            cmodel = c["model"] if c else "(none)"
            if p and c:
                mark = "same" if _spec_eq(p, c) else "CHANGE"
            else:
                mark = "CHANGE"
            lines.append(f"  {role:<8} {cmodel:<42} -> {pmodel:<42} {mark}")
        lines.append("")
    if not data.get("any_changed"):
        lines.append("No manifest changes — already matches this hardware plan.")
    else:
        lines.append("Proposed writes to config/*.manifest (install SSOT):")
        for c in data.get("changes") or []:
            lines.append(f"  - {c}")
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def cmd_probe(args: argparse.Namespace) -> int:
    probe = probe_machine(args.ram, args.chip)
    print(json.dumps(probe.to_dict(), indent=2))
    return 0


def cmd_match(args: argparse.Namespace) -> int:
    probe = probe_machine(args.ram, args.chip)
    hit = match_profile(probe)
    print(
        json.dumps(
            {
                "hardware": probe.to_dict(),
                "match": hit.to_dict() if hit else None,
            },
            indent=2,
        )
    )
    return 0


def cmd_plan(args: argparse.Namespace) -> int:
    data = build_plan(args.ram, args.chip, args.stack)
    print(json.dumps(data, indent=2))
    return 0


def cmd_apply(args: argparse.Namespace) -> int:
    data = json.loads(args.plan_json)
    stacks = data.get("stacks_requested") or list(ALL_STACKS)
    if args.stack:
        stacks = parse_stack_arg(args.stack)
    proposed = data.get("proposed") or {}
    written = apply_stacks(proposed, stacks)
    print(json.dumps({"written": written, "source": data.get("source")}, indent=2))
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="hw_profiles.py")
    sub = p.add_subparsers(dest="cmd", required=True)

    def add_hw(sp: argparse.ArgumentParser) -> None:
        sp.add_argument("--ram", type=float, default=None)
        sp.add_argument("--chip", default=None)

    pr = sub.add_parser("probe")
    add_hw(pr)
    pr.set_defaults(func=cmd_probe)

    m = sub.add_parser("match")
    add_hw(m)
    m.set_defaults(func=cmd_match)

    pl = sub.add_parser("plan")
    add_hw(pl)
    pl.add_argument("--stack", default="all")
    pl.set_defaults(func=cmd_plan)

    ap = sub.add_parser("apply")
    ap.add_argument("plan_json")
    ap.add_argument("--stack", default="")
    ap.set_defaults(func=cmd_apply)

    args = p.parse_args(argv)
    try:
        return args.func(args)
    except Exception as exc:  # noqa: BLE001
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
