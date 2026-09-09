"""Local image generation backend via mflux (MLX, Apple Silicon).

Wraps the ``mflux-generate-*`` CLIs installed by ``uv tool install mflux``
as an :class:`ImageGenProvider`. Fully local & free — no API key.

Models (weights pre-downloaded to ``~/models/image-gen/``,
see docs/image-gen.md in the local-llm repo):

- ``flux2-klein-4b`` — FLUX.2 Klein 4B 4bit, 4 steps, ~3s/768px on M5 Max.
  Supports text-to-image AND image editing (flux2-edit).
- ``z-image-turbo`` — Z-Image-Turbo 6B 4bit, 9 steps, realistic style.
  Text-to-image only.

Selection precedence:
1. ``image_gen.mflux.model`` in config.yaml
2. ``image_gen.model`` in config.yaml (when it's one of our IDs)
3. default: ``flux2-klein-4b``

Config keys (all optional, under ``image_gen.mflux``):
    model:       flux2-klein-4b | z-image-turbo
    models_dir:  weights root (default ~/models/image-gen)
    steps:       override sampling steps
"""

from __future__ import annotations

import logging
import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

from agent.image_gen_provider import (
    DEFAULT_ASPECT_RATIO,
    ImageGenProvider,
    error_response,
    resolve_aspect_ratio,
    success_response,
)

logger = logging.getLogger(__name__)

DEFAULT_MODELS_DIR = Path.home() / "models" / "image-gen"

# Hermes abstract aspect ratios → (width, height). Multiples of 16.
_ASPECT_SIZES = {
    "landscape": (1024, 576),
    "square": (768, 768),
    "portrait": (576, 1024),
}

_MODELS: Dict[str, Dict[str, Any]] = {
    "flux2-klein-4b": {
        "display": "FLUX.2 Klein 4B (local, mflux 4bit)",
        "speed": "~3-8s",
        "strengths": "General T2I + image editing. 4 steps. ~8GB peak RAM.",
        "price": "free (local)",
        "weights_dir": "FLUX.2-klein-4B-mflux-4bit",
        "cli": "mflux-generate-flux2",
        "edit_cli": "mflux-generate-flux2-edit",
        "base_model_arg": "flux2-klein-4b",
        "steps": 4,
    },
    "z-image-turbo": {
        "display": "Z-Image-Turbo 6B (local, mflux 4bit)",
        "speed": "~9-15s",
        "strengths": "Photorealistic style. 9 steps. ~8GB peak RAM.",
        "price": "free (local)",
        "weights_dir": "Z-Image-Turbo-mflux-4bit",
        "cli": "mflux-generate-z-image-turbo",
        "edit_cli": None,
        "base_model_arg": None,
        "steps": 9,
    },
}

DEFAULT_MODEL = "flux2-klein-4b"
_GENERATE_TIMEOUT = 420  # seconds; first run includes model load


def _mflux_config() -> Dict[str, Any]:
    try:
        from hermes_cli.config import load_config

        cfg = load_config()
        section = cfg.get("image_gen") if isinstance(cfg, dict) else None
        return section if isinstance(section, dict) else {}
    except Exception as exc:  # noqa: BLE001
        logger.debug("Could not load image_gen config: %s", exc)
        return {}


def _models_dir() -> Path:
    cfg = _mflux_config()
    sub = cfg.get("mflux") if isinstance(cfg.get("mflux"), dict) else {}
    raw = sub.get("models_dir") if isinstance(sub, dict) else None
    if isinstance(raw, str) and raw.strip():
        return Path(os.path.expanduser(raw.strip()))
    return DEFAULT_MODELS_DIR


def _resolve_model() -> str:
    cfg = _mflux_config()
    sub = cfg.get("mflux") if isinstance(cfg.get("mflux"), dict) else {}
    if isinstance(sub, dict):
        v = sub.get("model")
        if isinstance(v, str) and v in _MODELS:
            return v
    top = cfg.get("model")
    if isinstance(top, str) and top in _MODELS:
        return top
    return DEFAULT_MODEL


def _find_cli(name: str) -> Optional[str]:
    found = shutil.which(name)
    if found:
        return found
    candidate = Path.home() / ".local" / "bin" / name
    if candidate.is_file() and os.access(candidate, os.X_OK):
        return str(candidate)
    return None


def _images_cache_dir() -> Path:
    from hermes_constants import get_hermes_home

    path = get_hermes_home() / "cache" / "images"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _materialize_source_image(image_url: str) -> Optional[str]:
    """Return a local path for the edit source image (download URLs)."""
    if not isinstance(image_url, str) or not image_url.strip():
        return None
    src = image_url.strip()
    if src.startswith(("http://", "https://")):
        try:
            import requests

            resp = requests.get(src, timeout=60)
            resp.raise_for_status()
            fd, tmp = tempfile.mkstemp(suffix=".png", prefix="mflux_src_")
            with os.fdopen(fd, "wb") as fh:
                fh.write(resp.content)
            return tmp
        except Exception as exc:  # noqa: BLE001
            logger.warning("mflux: could not download source image %s: %s", src, exc)
            return None
    path = Path(os.path.expanduser(src))
    return str(path) if path.is_file() else None


class MfluxImageGenProvider(ImageGenProvider):
    """Local MLX image generation via the mflux CLI suite."""

    @property
    def name(self) -> str:
        return "mflux"

    @property
    def display_name(self) -> str:
        return "mflux (local MLX)"

    def is_available(self) -> bool:
        model_id = _resolve_model()
        meta = _MODELS[model_id]
        if _find_cli(meta["cli"]) is None:
            return False
        return (_models_dir() / meta["weights_dir"]).is_dir()

    def list_models(self) -> List[Dict[str, Any]]:
        return [
            {
                "id": mid,
                "display": m["display"],
                "speed": m["speed"],
                "strengths": m["strengths"],
                "price": m["price"],
            }
            for mid, m in _MODELS.items()
        ]

    def default_model(self) -> Optional[str]:
        return DEFAULT_MODEL

    def get_setup_schema(self) -> Dict[str, Any]:
        return {
            "name": "mflux (local MLX)",
            "badge": "free",
            "tag": (
                "Fully local image gen on Apple Silicon — FLUX.2 Klein 4B "
                "(~3s/image) + Z-Image-Turbo. No API key. Weights in "
                "~/models/image-gen/."
            ),
            "env_vars": [],
        }

    def capabilities(self) -> Dict[str, Any]:
        # FLUX.2 Klein supports editing; Z-Image-Turbo is text-only.
        model_id = _resolve_model()
        if _MODELS[model_id]["edit_cli"]:
            return {"modalities": ["text", "image"], "max_reference_images": 1}
        return {"modalities": ["text"], "max_reference_images": 0}

    def generate(
        self,
        prompt: str,
        aspect_ratio: str = DEFAULT_ASPECT_RATIO,
        *,
        image_url: Optional[str] = None,
        reference_image_urls: Optional[List[str]] = None,
        **kwargs: Any,
    ) -> Dict[str, Any]:
        prompt = (prompt or "").strip()
        aspect = resolve_aspect_ratio(aspect_ratio)
        width, height = _ASPECT_SIZES[aspect]
        model_id = _resolve_model()
        meta = _MODELS[model_id]

        if not prompt:
            return error_response(
                error="Prompt is required and must be a non-empty string",
                error_type="invalid_argument",
                provider="mflux",
                model=model_id,
                aspect_ratio=aspect,
            )

        weights = _models_dir() / meta["weights_dir"]
        if not weights.is_dir():
            return error_response(
                error=(
                    f"Model weights not found at {weights}. Download with "
                    "`lm pull-image` (see docs/image-gen.md in the local-llm repo)"
                ),
                error_type="not_configured",
                provider="mflux",
                model=model_id,
                prompt=prompt,
                aspect_ratio=aspect,
            )

        # Route: edit when a source image is given and the model supports it.
        source_path: Optional[str] = None
        modality = "text"
        cli_name = meta["cli"]
        if image_url and meta["edit_cli"]:
            source_path = _materialize_source_image(image_url)
            if source_path:
                cli_name = meta["edit_cli"]
                modality = "image"
            else:
                logger.warning(
                    "mflux: source image %r unusable; falling back to text-to-image",
                    image_url,
                )

        cli = _find_cli(cli_name)
        if cli is None:
            return error_response(
                error=(
                    f"mflux CLI '{cli_name}' not found. Install with "
                    "`uv tool install mflux`."
                ),
                error_type="not_configured",
                provider="mflux",
                model=model_id,
                prompt=prompt,
                aspect_ratio=aspect,
            )

        cfg = _mflux_config()
        sub = cfg.get("mflux") if isinstance(cfg.get("mflux"), dict) else {}
        steps = meta["steps"]
        if isinstance(sub, dict) and isinstance(sub.get("steps"), int) and sub["steps"] > 0:
            steps = sub["steps"]

        ts = time.strftime("%Y%m%d_%H%M%S")
        out_path = _images_cache_dir() / f"mflux_{model_id}_{ts}_{os.getpid()}.png"

        cmd = [
            cli,
            "--model", str(weights),
            "--prompt", prompt,
            "--width", str(width),
            "--height", str(height),
            "--steps", str(steps),
            "--output", str(out_path),
        ]
        if meta["base_model_arg"]:
            cmd += ["--base-model", meta["base_model_arg"]]
        if source_path:
            cmd += ["--image-path", source_path]
        seed = kwargs.get("seed")
        if isinstance(seed, int):
            cmd += ["--seed", str(seed)]

        logger.info("mflux: running %s (%dx%d, %d steps)", cli_name, width, height, steps)
        try:
            proc = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=_GENERATE_TIMEOUT,
            )
        except subprocess.TimeoutExpired:
            return error_response(
                error=f"mflux generation timed out ({_GENERATE_TIMEOUT}s)",
                error_type="timeout",
                provider="mflux",
                model=model_id,
                prompt=prompt,
                aspect_ratio=aspect,
            )
        finally:
            if source_path and source_path.startswith(tempfile.gettempdir()):
                try:
                    os.unlink(source_path)
                except OSError:
                    pass

        if proc.returncode != 0 or not out_path.is_file():
            tail = (proc.stderr or proc.stdout or "").strip()[-600:]
            return error_response(
                error=f"mflux failed (exit {proc.returncode}): {tail}",
                error_type="provider_error",
                provider="mflux",
                model=model_id,
                prompt=prompt,
                aspect_ratio=aspect,
            )

        return success_response(
            image=str(out_path),
            model=model_id,
            prompt=prompt,
            aspect_ratio=aspect,
            provider="mflux",
            modality=modality,
        )


def register(ctx) -> None:
    """Plugin entry point — wire the mflux backend into the registry."""
    ctx.register_image_gen_provider(MfluxImageGenProvider())
