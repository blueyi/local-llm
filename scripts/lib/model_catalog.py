#!/usr/bin/env python3
"""Remote Ollama catalog helpers for `lm update` / `lm get`.

Stdlib only. Discovers models from ollama.com, scores them against local
hardware + update-policy.conf, and emits machine-readable recommendations.
"""
from __future__ import annotations

import argparse
import difflib
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import asdict, dataclass, field
from html import unescape
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_POLICY = ROOT / "config" / "update-policy.conf"
DEFAULT_MANIFEST = ROOT / "config" / "models.manifest"
UA = "local-llm-lm/1.0 (+https://github.com/local-llm)"


# ---------------------------------------------------------------------------
# Policy / hardware
# ---------------------------------------------------------------------------


def load_policy(path: Path) -> dict[str, str]:
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


@dataclass
class Hardware:
    mem_gb: float
    chip: str
    reserve_gb: float
    usable_gb: float
    source: str  # auto | override

    def to_dict(self) -> dict:
        return asdict(self)


def detect_hardware(
    policy: dict[str, str],
    ram_gb: float | None = None,
    chip: str | None = None,
) -> Hardware:
    reserve = _f(policy, "RESERVE_GB", 12.0)
    source = "override" if ram_gb is not None else "auto"
    detected_chip = chip or ""
    detected_mem = ram_gb

    if detected_mem is None or not detected_chip:
        # macOS / Linux best-effort
        try:
            import platform
            import subprocess

            system = platform.system()
            if system == "Darwin":
                if detected_mem is None:
                    out = subprocess.check_output(
                        ["sysctl", "-n", "hw.memsize"], text=True
                    ).strip()
                    detected_mem = int(out) / (1024**3)
                if not detected_chip:
                    detected_chip = subprocess.check_output(
                        ["sysctl", "-n", "machdep.cpu.brand_string"], text=True
                    ).strip()
            elif system == "Linux":
                if detected_mem is None:
                    mem_kb = None
                    with open("/proc/meminfo", encoding="utf-8") as fh:
                        for line in fh:
                            if line.startswith("MemTotal:"):
                                mem_kb = int(line.split()[1])
                                break
                    if mem_kb:
                        detected_mem = mem_kb / (1024**2)
                if not detected_chip:
                    try:
                        with open("/proc/cpuinfo", encoding="utf-8") as fh:
                            for line in fh:
                                if line.startswith("model name"):
                                    detected_chip = line.split(":", 1)[1].strip()
                                    break
                    except OSError:
                        pass
        except Exception as exc:  # noqa: BLE001 — best-effort probe
            print(f"warn: hardware probe failed: {exc}", file=sys.stderr)

    if detected_mem is None:
        detected_mem = 48.0
        print(
            "warn: could not detect RAM; defaulting to 48GB (pass --ram)",
            file=sys.stderr,
        )
        source = "default"
    if not detected_chip:
        detected_chip = "unknown"

    usable = max(4.0, float(detected_mem) - reserve)
    return Hardware(
        mem_gb=round(float(detected_mem), 1),
        chip=detected_chip,
        reserve_gb=reserve,
        usable_gb=round(usable, 1),
        source=source,
    )


# ---------------------------------------------------------------------------
# HTTP + parsing
# ---------------------------------------------------------------------------


def http_get(url: str, accept: str | None = None, timeout: int = 30) -> bytes:
    headers = {"User-Agent": UA}
    if accept:
        headers["Accept"] = accept
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def http_get_text(url: str, accept: str | None = None, timeout: int = 30) -> str:
    return http_get(url, accept=accept, timeout=timeout).decode("utf-8", "replace")


@dataclass
class FamilyInfo:
    name: str
    description: str = ""
    badges: list[str] = field(default_factory=list)

    @property
    def has_vision(self) -> bool:
        return any(b.lower() == "vision" for b in self.badges)

    @property
    def has_tools(self) -> bool:
        return any(b.lower() == "tools" for b in self.badges)


@dataclass
class TagInfo:
    family: str
    tag: str  # variant only (no family prefix); empty means bare family / latest alias
    full: str  # family or family:tag
    size_gb: float
    context: str = ""
    digest: str = ""

    def to_dict(self) -> dict:
        return asdict(self)


def search_families(
    query: str, base: str, limit: int = 30
) -> list[FamilyInfo]:
    """Search ollama.com library; returns unique family names with metadata."""
    url = f"{base.rstrip('/')}/search?q={urllib.parse.quote(query)}"
    html = http_get_text(url)
    results: list[FamilyInfo] = []
    seen: set[str] = set()

    # Card pattern from search results page
    card_re = re.compile(
        r'href="/library/([^"#?]+)"[^>]*>\s*'
        r'<div class="flex flex-col mb-1"[^>]*title="([^"]*)"[\s\S]*?'
        r'<p class="max-w-lg[^"]*">([^<]*)</p>([\s\S]*?)</a>',
        re.I,
    )
    for m in card_re.finditer(html):
        name = unescape(m.group(1)).strip()
        if ":" in name or name in seen:
            continue
        seen.add(name)
        desc = unescape(m.group(3)).strip()
        rest = m.group(4)
        badges = [
            unescape(b).strip()
            for b in re.findall(
                r"text-(?:indigo|blue)-600[^>]*>([^<]+)", rest
            )
            if unescape(b).strip()
        ]
        # Also catch plain size badges like 9b / 35b in blue chips
        results.append(FamilyInfo(name=name, description=desc, badges=badges))
        if len(results) >= limit:
            break

    if results:
        return results

    # Fallback: HTMX-style / simpler href scrape
    for name in re.findall(r'href="/library/([A-Za-z0-9._-]+)"', html):
        if ":" in name or name in seen:
            continue
        seen.add(name)
        results.append(FamilyInfo(name=name))
        if len(results) >= limit:
            break
    return results


def fetch_family_meta(name: str, base: str) -> FamilyInfo:
    url = f"{base.rstrip('/')}/library/{urllib.parse.quote(name)}"
    try:
        html = http_get_text(url)
    except Exception:  # noqa: BLE001
        return FamilyInfo(name=name)
    desc = ""
    m = re.search(
        r'<meta\s+name="description"\s+content="([^"]*)"', html, re.I
    )
    if m:
        desc = unescape(m.group(1)).strip()
    badges = [
        unescape(b).strip()
        for b in re.findall(
            r"text-(?:indigo|blue)-600[^>]*>([^<]+)", html[:20000]
        )
        if unescape(b).strip() and len(unescape(b).strip()) < 24
    ]
    # Dedupe preserving order
    uniq: list[str] = []
    for b in badges:
        if b not in uniq:
            uniq.append(b)
    return FamilyInfo(name=name, description=desc, badges=uniq)


def fetch_tags(family: str, base: str, registry: str) -> list[TagInfo]:
    """Fetch tags + sizes for a family. Prefer HTML parse; fill gaps via registry."""
    tags_url = f"{base.rstrip('/')}/library/{urllib.parse.quote(family)}/tags"
    html = http_get_text(tags_url)
    # Accurate row pattern from mobile tag cards
    row_re = re.compile(
        rf"{re.escape(family)}:([A-Za-z0-9._-]+)</span>"
        r".*?font-mono[^>]*>\s*([0-9a-f]+)</span>\s*•\s*"
        r"([\d.]+)\s*(GB|MB|TB)\s*•\s*(\d+K)\s*context",
        re.S | re.I,
    )
    out: list[TagInfo] = []
    seen: set[str] = set()
    for m in row_re.finditer(html):
        tag = m.group(1)
        if tag in seen:
            continue
        seen.add(tag)
        size = float(m.group(3))
        unit = m.group(4).upper()
        if unit == "MB":
            size /= 1024.0
        elif unit == "TB":
            size *= 1024.0
        out.append(
            TagInfo(
                family=family,
                tag=tag,
                full=f"{family}:{tag}",
                size_gb=round(size, 2),
                context=m.group(5),
                digest=m.group(2),
            )
        )

    # JSON tag list may include tags missing from HTML parse
    try:
        payload = json.loads(
            http_get_text(tags_url, accept="application/json")
        )
        json_tags = payload.get("tags") or []
    except Exception:  # noqa: BLE001
        json_tags = []

    for tag in json_tags:
        if not tag or tag in seen:
            continue
        size = registry_size_gb(family, tag, registry)
        if size is None:
            continue
        seen.add(tag)
        out.append(
            TagInfo(
                family=family,
                tag=tag,
                full=f"{family}:{tag}",
                size_gb=round(size, 2),
            )
        )
    return out


def registry_size_gb(family: str, tag: str, registry: str) -> float | None:
    ref = tag or "latest"
    url = (
        f"{registry.rstrip('/')}/v2/library/{urllib.parse.quote(family)}"
        f"/manifests/{urllib.parse.quote(ref)}"
    )
    try:
        raw = http_get(
            url,
            accept="application/vnd.docker.distribution.manifest.v2+json",
            timeout=20,
        )
        data = json.loads(raw.decode())
        total = sum(int(l.get("size", 0)) for l in data.get("layers", []))
        total += int(data.get("config", {}).get("size", 0) or 0)
        if total <= 0:
            return None
        return total / 1e9
    except Exception:  # noqa: BLE001
        return None


# ---------------------------------------------------------------------------
# Scoring / recommendation
# ---------------------------------------------------------------------------


def _excluded(tag: str, substrs: list[str]) -> bool:
    low = tag.lower()
    return any(s.lower() in low for s in substrs if s)


def _quant_rank(tag: str, prefer: list[str]) -> int:
    low = tag.lower()
    for i, q in enumerate(prefer):
        if q.lower() in low:
            return i
    # bare size tags like "9b" / "latest" — middling
    if re.fullmatch(r"(latest|\d+b(-\w+)?)", low):
        return len(prefer)
    return len(prefer) + 2


def _is_moe(tag: str) -> bool:
    return bool(re.search(r"a\d+b", tag.lower()))


def _param_b(tag: str) -> float | None:
    m = re.search(r"(?:^|-)(\d+(?:\.\d+)?)b(?:-|$)", tag.lower())
    if m:
        return float(m.group(1))
    return None


def tier_window(
    tier: str, hw: Hardware, policy: dict[str, str]
) -> tuple[float, float]:
    prefix = tier.upper()
    lo = hw.usable_gb * _f(policy, f"{prefix}_FRAC_MIN", 0.1)
    hi = hw.usable_gb * _f(policy, f"{prefix}_FRAC_MAX", 0.9)
    abs_max = _f(policy, f"{prefix}_ABS_MAX", hi)
    hi = min(hi, abs_max, hw.usable_gb)
    lo = min(lo, hi)
    return (round(lo, 2), round(hi, 2))


def score_tag(
    tier: str,
    tag: TagInfo,
    family: FamilyInfo,
    hw: Hardware,
    policy: dict[str, str],
) -> float | None:
    """Return score (higher=better) or None if ineligible."""
    exclude = _csv(policy, "EXCLUDE_TAG_SUBSTR")
    if _excluded(tag.tag, exclude) or _excluded(tag.full, exclude):
        return None

    lo, hi = tier_window(tier, hw, policy)
    if tag.size_gb < lo * 0.85 or tag.size_gb > hi * 1.02:
        # slight soft floor for fast small models
        if not (tier == "fast" and tag.size_gb <= hi):
            return None
        if tag.size_gb < lo * 0.5 and tier != "fast":
            return None

    quant_key = {
        "main": "MAIN_QUANT_PREFER",
        "deep": "DEEP_QUANT_PREFER",
        "fast": "FAST_QUANT_PREFER",
    }[tier]
    prefer = _csv(policy, quant_key)
    score = 100.0

    # Size sweet-spot: closer to mid-window is better for main; deep prefers larger
    mid = (lo + hi) / 2
    if tier == "deep":
        target = hi * 0.9
    elif tier == "fast":
        target = min(7.0, hi * 0.7)
    else:
        target = mid
    score -= abs(tag.size_gb - target) * 1.5

    score -= _quant_rank(tag.tag, prefer) * 4

    if policy.get("PREFER_VISION", "1") == "1" and family.has_vision:
        score += 12
    if policy.get("PREFER_TOOLS", "1") == "1" and family.has_tools:
        score += 8

    moe = _is_moe(tag.tag)
    if tier == "main" and policy.get("MAIN_PREFER_MOE", "1") == "1":
        score += 10 if moe else -6
    if tier == "deep" and policy.get("DEEP_PREFER_DENSE", "1") == "1":
        score += 10 if not moe else -8

    # Prefer explicit quant tags over vague aliases for reproducibility,
    # but keep the penalty mild so short library defaults (e.g. 9b) stay stable.
    if tag.tag in ("latest",) or re.fullmatch(r"\d+b", tag.tag.lower() or ""):
        score -= 2

    # Prefer coding variants slightly for main/deep when present
    if "coding" in tag.tag.lower() and tier in ("main", "deep"):
        score += 3

    # MTP / speculative-decoding builds are optional swaps, not default upgrades
    if "mtp" in tag.tag.lower():
        score -= 6

    # Prefer known good families via order bonus applied by caller
    return score


def _same_lineup(a: str, b: str, size_a: float | None, size_b: float | None) -> bool:
    """True when tags are effectively the same install target (alias / quant suffix)."""
    if not a or not b:
        return False
    if a == b:
        return True
    if size_a is not None and size_b is not None and abs(size_a - size_b) > 0.75:
        return False
    fa, _, ta = a.partition(":")
    fb, _, tb = b.partition(":")
    if fa != fb:
        return False
    ta, tb = ta.lower(), tb.lower()
    if not ta or not tb:
        return ta == tb
    return ta == tb or tb.startswith(ta + "-") or ta.startswith(tb + "-")


def recommend_tiers(
    hw: Hardware,
    policy: dict[str, str],
    current: dict[str, str],
) -> dict[str, dict]:
    base = policy.get("OLLAMA_LIBRARY_BASE", "https://ollama.com")
    registry = policy.get("OLLAMA_REGISTRY_BASE", "https://registry.ollama.ai")
    families = _csv(policy, "FAMILIES")
    watch = _csv(policy, "WATCH_FAMILIES")

    family_metas: dict[str, FamilyInfo] = {}
    all_tags: list[tuple[FamilyInfo, TagInfo, int]] = []  # priority index

    for pri, name in enumerate(families + watch):
        try:
            meta = fetch_family_meta(name, base)
            tags = fetch_tags(name, base, registry)
        except Exception as exc:  # noqa: BLE001
            print(f"warn: skip family {name}: {exc}", file=sys.stderr)
            continue
        family_metas[name] = meta
        for t in tags:
            all_tags.append((meta, t, pri))

    picks: dict[str, dict] = {}
    used_full: set[str] = set()

    # Keep current lineup unless a challenger beats it by a clear margin
    stability = _f(policy, "STABILITY_MARGIN", 4.0)

    for tier in ("main", "deep", "fast"):
        ranked: list[tuple[float, TagInfo, FamilyInfo]] = []
        for meta, tag, pri in all_tags:
            if tag.full in used_full:
                continue
            s = score_tag(tier, tag, meta, hw, policy)
            if s is None:
                continue
            # Family priority: preferred list beats watch list
            s -= pri * 3
            ranked.append((s, tag, meta))
        ranked.sort(key=lambda x: x[0], reverse=True)
        lo, hi = tier_window(tier, hw, policy)
        if not ranked:
            picks[tier] = {
                "tier": tier,
                "full": current.get(tier, ""),
                "size_gb": None,
                "score": None,
                "changed": False,
                "reason": "no eligible remote candidate in size window "
                f"{lo}-{hi}GB; keeping current",
                "window": [lo, hi],
                "family_badges": [],
            }
            continue

        best_s, best_t, best_f = ranked[0]
        cur = current.get(tier, "")
        # Stability: prefer current if still eligible and within margin of best
        cur_entry = next((x for x in ranked if x[1].full == cur), None)
        if cur_entry and (best_s - cur_entry[0]) < stability:
            best_s, best_t, best_f = cur_entry
        # Alias stability: e.g. qwen3.5:9b vs qwen3.5:9b-q4_K_M (same weights)
        if cur_entry and _same_lineup(
            cur, best_t.full, cur_entry[1].size_gb, best_t.size_gb
        ):
            best_s, best_t, best_f = cur_entry

        changed = best_t.full != cur
        # If we couldn't re-score current but proposed is an alias, keep current
        if changed and cur and _same_lineup(cur, best_t.full, None, best_t.size_gb):
            changed = False
            best_t = TagInfo(
                family=cur.split(":", 1)[0],
                tag=cur.split(":", 1)[1] if ":" in cur else "",
                full=cur,
                size_gb=best_t.size_gb,
                context=best_t.context,
            )
        picks[tier] = {
            "tier": tier,
            "full": best_t.full,
            "tag": best_t.tag,
            "family": best_t.family,
            "size_gb": best_t.size_gb,
            "context": best_t.context,
            "score": round(best_s, 2),
            "changed": changed,
            "current": cur,
            "reason": "best fit" if changed else "already optimal",
            "window": [lo, hi],
            "family_badges": best_f.badges,
            "alternatives": [
                {
                    "full": t.full,
                    "size_gb": t.size_gb,
                    "score": round(s, 2),
                }
                for s, t, _ in ranked
                if t.full != best_t.full
            ][:3],
        }
        used_full.add(best_t.full)

    return picks


# ---------------------------------------------------------------------------
# Fuzzy get
# ---------------------------------------------------------------------------


def fuzzy_filter(query: str, names: Iterable[str], limit: int = 20) -> list[str]:
    """Rank names by fuzzy relevance. Exact match ranks first but related hits remain."""
    q = query.lower().strip()
    names = list(names)
    if not q:
        return names[:limit]

    scored: list[tuple[float, str]] = []
    for n in names:
        nl = n.lower()
        if nl == q:
            scored.append((1.0, n))
            continue
        # Candidate extends the query (qwen3 -> qwen3.6 / 35b-a3b-q4 -> 35b-a3b-q4_K_M)
        if nl.startswith(q):
            scored.append((0.97, n))
            continue
        if q in nl:
            scored.append((0.93, n))
            continue
        # Query extends a short candidate (35b-a3b-q4 starts with 35b) — weaker
        if q.startswith(nl + "-") or q.startswith(nl + ":") or q.startswith(nl + "."):
            scored.append((0.72, n))
            continue
        if q.startswith(nl) and len(nl) >= 4:
            scored.append((0.68, n))
            continue
        if nl in q and len(nl) >= 4:
            scored.append((0.65, n))
            continue
        ratio = difflib.SequenceMatcher(None, q, nl).ratio()
        tokens = [tok for tok in re.split(r"[:\s/_-]+", q) if tok]
        if tokens and all(tok in nl for tok in tokens):
            ratio = max(ratio, 0.85)
        if ratio >= 0.45:
            scored.append((ratio, n))
    scored.sort(key=lambda x: (-x[0], -len(x[1]), x[1]))
    out: list[str] = []
    seen: set[str] = set()
    for _, n in scored:
        if n in seen:
            continue
        seen.add(n)
        out.append(n)
        if len(out) >= limit:
            break
    return out


def resolve_get_candidates(
    query: str, policy: dict[str, str]
) -> dict:
    """Resolve a user query into family/tag candidates for interactive selection."""
    base = policy.get("OLLAMA_LIBRARY_BASE", "https://ollama.com")
    registry = policy.get("OLLAMA_REGISTRY_BASE", "https://registry.ollama.ai")
    q = query.strip()
    family_part, tag_part = (q.split(":", 1) + [""])[:2]
    family_part = family_part.strip()
    tag_part = tag_part.strip()

    # Search families
    families = search_families(family_part or q, base)
    fam_names = [f.name for f in families]
    # Also include exact family_part if search missed it
    if family_part and family_part not in fam_names:
        try:
            fetch_tags(family_part, base, registry)
            fam_names.insert(0, family_part)
            families.insert(0, FamilyInfo(name=family_part))
        except Exception:  # noqa: BLE001
            pass

    matched_families = fuzzy_filter(family_part or q, fam_names)

    # Tag-only / weak family queries: fall back to policy families and
    # treat the whole query as a tag filter (e.g. "35b-a3b-q4").
    tag_only = False
    if not matched_families or (
        ":" not in q
        and matched_families
        and all(m.lower() != family_part.lower() for m in matched_families)
        and not any(family_part.lower() in m.lower() for m in matched_families)
    ):
        # If search returned nothing useful, scan preferred families for tag hits
        prefer = _csv(policy, "FAMILIES") + _csv(policy, "WATCH_FAMILIES")
        tag_query = tag_part or q
        hit_families: list[str] = []
        details: dict[str, dict] = {}
        for name in prefer:
            try:
                tags = fetch_tags(name, base, registry)
            except Exception:  # noqa: BLE001
                continue
            matched_tags = fuzzy_filter(tag_query, [t.tag for t in tags], limit=5)
            if not matched_tags and fuzzy_filter(tag_query, [t.full for t in tags], limit=5):
                matched_tags = ["*"]
            # Also match against full name
            if not matched_tags:
                for t in tags:
                    if tag_query.lower() in t.full.lower() or tag_query.lower() in t.tag.lower():
                        matched_tags = [t.tag]
                        break
            if matched_tags:
                hit_families.append(name)
                meta = fetch_family_meta(name, base)
                details[name] = {
                    "description": meta.description,
                    "badges": meta.badges,
                }
        if hit_families:
            tag_only = True
            return {
                "query": q,
                "family_query": "",
                "tag_query": tag_query,
                "families": hit_families,
                "family_details": details,
                "tag_only": True,
            }

    return {
        "query": q,
        "family_query": family_part,
        "tag_query": tag_part,
        "families": matched_families,
        "family_details": {
            f.name: {"description": f.description, "badges": f.badges}
            for f in families
            if f.name in matched_families
        },
        "tag_only": tag_only,
    }


def list_tags_for_family(family: str, policy: dict[str, str], tag_query: str = "") -> list[dict]:
    base = policy.get("OLLAMA_LIBRARY_BASE", "https://ollama.com")
    registry = policy.get("OLLAMA_REGISTRY_BASE", "https://registry.ollama.ai")
    tags = fetch_tags(family, base, registry)
    names = [t.tag for t in tags]
    if tag_query:
        matched = fuzzy_filter(tag_query, names, limit=50)
        tags = [t for t in tags if t.tag in matched]
        # Preserve fuzzy order
        order = {n: i for i, n in enumerate(matched)}
        tags.sort(key=lambda t: order.get(t.tag, 999))
    return [t.to_dict() for t in tags]


# ---------------------------------------------------------------------------
# Manifest helpers
# ---------------------------------------------------------------------------


def read_manifest_tiers(path: Path) -> dict[str, dict]:
    tiers: dict[str, dict] = {}
    if not path.is_file():
        return tiers
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#") or "|" not in line:
            continue
        parts = line.split("|")
        tier = parts[0].strip()
        if tier not in ("main", "deep", "fast", "embed", "chat", "reason", "rerank"):
            continue
        tiers[tier] = {
            "tier": tier,
            "tag": parts[1].strip() if len(parts) > 1 else "",
            "num_ctx": parts[2].strip() if len(parts) > 2 else "",
            "gguf_url": parts[3].strip() if len(parts) > 3 else "",
            "mmproj_url": parts[4].strip() if len(parts) > 4 else "",
            "raw": line,
        }
    return tiers


def apply_manifest_updates(
    path: Path,
    updates: dict[str, str],
    ctx_map: dict[str, int],
) -> list[str]:
    """Rewrite tier lines in models.manifest. Clears HF URLs when tag changes.
    Returns list of human-readable change descriptions.
    """
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    changes: list[str] = []
    new_lines: list[str] = []
    for line in lines:
        raw = line.rstrip("\n")
        if not raw or raw.startswith("#") or "|" not in raw:
            new_lines.append(line)
            continue
        parts = raw.split("|")
        tier = parts[0].strip()
        if tier not in updates:
            new_lines.append(line)
            continue
        old_tag = parts[1].strip() if len(parts) > 1 else ""
        new_tag = updates[tier]
        if old_tag == new_tag:
            new_lines.append(line)
            continue
        while len(parts) < 5:
            parts.append("")
        parts[1] = new_tag
        if tier in ctx_map:
            parts[2] = str(ctx_map[tier])
        # Drop GGUF fallbacks when switching tags (may not match)
        parts[3] = ""
        parts[4] = ""
        new_line = "|".join(parts)
        nl = "\n" if line.endswith("\n") else ""
        new_lines.append(new_line + nl)
        changes.append(f"{tier}: {old_tag} -> {new_tag}")
    if changes:
        path.write_text("".join(new_lines), encoding="utf-8")
    return changes


# ---------------------------------------------------------------------------
# CLI entrypoints used by bash wrappers
# ---------------------------------------------------------------------------


def cmd_detect(args: argparse.Namespace) -> int:
    policy = load_policy(Path(args.policy))
    hw = detect_hardware(policy, args.ram, args.chip)
    print(json.dumps(hw.to_dict(), indent=2))
    return 0


def cmd_recommend(args: argparse.Namespace) -> int:
    policy = load_policy(Path(args.policy))
    hw = detect_hardware(policy, args.ram, args.chip)
    manifest = read_manifest_tiers(Path(args.manifest))
    current = {t: manifest[t]["tag"] for t in manifest}
    picks = recommend_tiers(hw, policy, current)
    out = {
        "hardware": hw.to_dict(),
        "current": current,
        "recommendations": picks,
        "any_changed": any(p.get("changed") for p in picks.values()),
    }
    print(json.dumps(out, indent=2))
    return 0


def cmd_search(args: argparse.Namespace) -> int:
    policy = load_policy(Path(args.policy))
    result = resolve_get_candidates(args.query, policy)
    print(json.dumps(result, indent=2))
    return 0


def cmd_tags(args: argparse.Namespace) -> int:
    policy = load_policy(Path(args.policy))
    tags = list_tags_for_family(args.family, policy, args.tag_query or "")
    print(json.dumps({"family": args.family, "tags": tags}, indent=2))
    return 0


def cmd_apply_manifest(args: argparse.Namespace) -> int:
    policy = load_policy(Path(args.policy))
    updates = json.loads(args.updates_json)
    ctx_map = {
        "main": _i(policy, "MAIN_NUM_CTX", 65536),
        "deep": _i(policy, "DEEP_NUM_CTX", 32768),
        "fast": _i(policy, "FAST_NUM_CTX", 32768),
        "embed": _i(policy, "EMBED_NUM_CTX", 8192),
        "chat": _i(policy, "CHAT_NUM_CTX", 65536),
        "reason": _i(policy, "REASON_NUM_CTX", 65536),
        "rerank": _i(policy, "RERANK_NUM_CTX", 8192),
    }
    changes = apply_manifest_updates(Path(args.manifest), updates, ctx_map)
    print(json.dumps({"changes": changes}, indent=2))
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="model_catalog.py")
    p.add_argument("--policy", default=str(DEFAULT_POLICY))
    p.add_argument("--manifest", default=str(DEFAULT_MANIFEST))
    sub = p.add_subparsers(dest="cmd", required=True)

    d = sub.add_parser("detect")
    d.add_argument("--ram", type=float, default=None)
    d.add_argument("--chip", default=None)
    d.set_defaults(func=cmd_detect)

    r = sub.add_parser("recommend")
    r.add_argument("--ram", type=float, default=None)
    r.add_argument("--chip", default=None)
    r.set_defaults(func=cmd_recommend)

    s = sub.add_parser("search")
    s.add_argument("query")
    s.set_defaults(func=cmd_search)

    t = sub.add_parser("tags")
    t.add_argument("family")
    t.add_argument("--tag-query", default="")
    t.set_defaults(func=cmd_tags)

    a = sub.add_parser("apply-manifest")
    a.add_argument("updates_json", help='JSON object {"main":"tag",...}')
    a.set_defaults(func=cmd_apply_manifest)

    args = p.parse_args(argv)
    try:
        return args.func(args)
    except urllib.error.URLError as exc:
        print(f"error: network failure talking to Ollama library: {exc}", file=sys.stderr)
        return 2
    except Exception as exc:  # noqa: BLE001
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
