"""Stage 2 of the local battle bridge. Network transport is supplied by ai_bridge."""

from __future__ import annotations

import base64
from collections import OrderedDict
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from functools import lru_cache
import hashlib
import io
import json
import os
from pathlib import Path
import re
import struct
import tempfile
import threading
import time
import unicodedata

try:
    import numpy as np
    from PIL import Image, ImageDraw
except ImportError:
    np = Image = ImageDraw = None


ROOT = Path(__file__).resolve().parent
IMAGING_AVAILABLE = Image is not None
LIVE_PROMPT_LIMIT = 12
PURPLE_WORDS = {"berenjena", "pulpo", "uva", "uvas", "violeta", "morado", "morada", "purpura", "purple"}


def live_prompt(value):
    text = value.strip() if isinstance(value, str) else ""
    return text if 2 <= len(text) <= LIVE_PROMPT_LIMIT else ""


def _words(text):
    decomposed = unicodedata.normalize("NFKD", text.casefold())
    plain = "".join(c for c in decomposed if not unicodedata.combining(c))
    return re.findall(r"[^\W_]+", plain, flags=re.UNICODE)


@lru_cache(maxsize=1)
def _rules():
    with (ROOT / "battle_rules.json").open(encoding="utf-8") as rules:
        return json.load(rules)


def _canonical_sprite_key(text):
    words = _words(text)
    while words and words[0] in _rules()["prefixes"]:
        words.pop(0)
    return " ".join(words)


@lru_cache(maxsize=1)
def _sprite_aliases():
    sprites = _rules()["sprites"]
    return {_canonical_sprite_key(alias): sprite for sprite, aliases in sprites.items()
            for alias in [sprite, *aliases]}


def match_exact_existing_sprite(prompt):
    if not isinstance(prompt, str):
        return None
    return _sprite_aliases().get(_canonical_sprite_key(prompt))


def _png(image):
    output = io.BytesIO()
    image.save(output, format="PNG")
    return output.getvalue()


def _clean_corner_bg_floodfill(pixels, keep_purple):
    """Erase the solid key and connected antialias fringe, preserving interior colors."""
    rgb = pixels[:, :, :3].astype(np.int16)
    red, green, blue = rgb.transpose(2, 0, 1)
    core = (red >= 232) & (green <= 32) & (blue >= 232)
    if keep_purple:
        fringe = (red >= 218) & (green < 62) & (blue >= 218)
    else:
        fringe = (red >= 158) & (blue >= 150) & (np.abs(red - blue) < 90) & (green < np.minimum(red, blue) * 0.52)
    # One padded border connects all four edges. Pillow uses a four-neighbour
    # breadth-first fill; isolated costume highlights are never flood-filled.
    candidates = fringe | (pixels[:, :, 3] == 0)
    mask = Image.fromarray(np.pad(candidates, 1, constant_values=True).astype("uint8")).copy()
    ImageDraw.floodfill(mask, (0, 0), 2)
    removed = core | (np.asarray(mask)[1:-1, 1:-1] == 2)
    pixels[removed] = 0


def generate_normal_map(sprite, strength=2.4, dome_weight=0.45):
    pixels = np.asarray(sprite, dtype=np.float32) / 255.0
    alpha = pixels[:, :, 3]
    yy, xx = np.indices(alpha.shape)
    left, top, right, bottom = sprite.getchannel("A").getbbox()
    x = (2 * xx + 1 - (left + right)) / max(right - left, 1)
    y = (2 * yy + 1 - (top + bottom)) / max(bottom - top, 1)
    dome = np.sqrt(np.maximum(1.0 - x * x - y * y, 0.0))
    luminance = pixels[:, :, :3] @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    height = np.pad(alpha * ((1 - dome_weight) * luminance + dome_weight * dome), 1)
    dx = (height[:-2, 2:] + 2 * height[1:-1, 2:] + height[2:, 2:]
          - height[:-2, :-2] - 2 * height[1:-1, :-2] - height[2:, :-2]) / 8
    dy = (height[2:, :-2] + 2 * height[2:, 1:-1] + height[2:, 2:]
          - height[:-2, :-2] - 2 * height[:-2, 1:-1] - height[:-2, 2:]) / 8
    normal = np.stack((-strength * dx, strength * dy, np.ones_like(dx)), axis=2)
    normal /= np.linalg.norm(normal, axis=2, keepdims=True)
    normal[alpha == 0] = (0, 0, 1)
    rgba = np.dstack(((normal + 1) * 127.5, alpha * 255))
    return Image.fromarray(np.rint(rgba).astype("uint8"))


@dataclass(frozen=True)
class SpritePair:
    diffuse: bytes
    normal: bytes
    width: int
    height: int


def _prepare_sprite(raw, keep_purple, dim):
    with Image.open(io.BytesIO(raw)) as source:
        if source.width * source.height > 16_777_216:
            raise ValueError("La imagen supera el tamaño admitido.")
        image = source.convert("RGBA")
    image.thumbnail((384, 384), Image.Resampling.NEAREST)
    pixels = np.array(image)
    _clean_corner_bg_floodfill(pixels, keep_purple)
    corners = pixels[[0, 0, -1, -1], [0, -1, 0, -1], 3]
    if np.count_nonzero(corners) > 1:
        raise ValueError("No se pudo aislar la silueta del sprite.")
    clean = Image.fromarray(pixels)
    box = clean.getchannel("A").getbbox()
    if box is None or np.count_nonzero(pixels[:, :, 3]) < 16:
        raise ValueError("El sprite llegó vacío.")
    cropped = clean.crop(box)
    scale = (dim - 2) / max(cropped.size)
    cropped = cropped.resize(tuple(max(1, round(v * scale)) for v in cropped.size), Image.Resampling.NEAREST)
    sprite = Image.new("RGBA", (dim, dim))
    sprite.paste(cropped, ((dim - cropped.width) // 2, dim - cropped.height))
    return SpritePair(_png(sprite), _png(generate_normal_map(sprite)), dim, dim)


def _reference(path):
    if not path.is_file():
        return None
    with Image.open(path) as image:
        hero = image.convert("RGBA")
    hero.thumbnail((128, 128), Image.Resampling.NEAREST)
    canvas = Image.new("RGBA", (128, 128), "#FF00FF")
    canvas.alpha_composite(hero, ((128 - hero.width) // 2, (128 - hero.height) // 2))
    return _png(canvas.convert("RGB"))


def _bundled_sprite(asset):
    assets = ROOT / "assets"
    for directory in (assets / "custom", assets / "sprites/gags", assets / "sprites/props", assets / "sprites"):
        path = directory / f"{asset}.png"
        if path.is_file():
            with Image.open(path) as opened:
                diffuse = opened.convert("RGBA")
            normal_path = directory / f"{asset}_n.png"
            if normal_path.is_file():
                with Image.open(normal_path) as opened:
                    normal = opened.convert("RGBA")
                if normal.size == diffuse.size:
                    return SpritePair(_png(diffuse), _png(normal), *diffuse.size)
            return SpritePair(_png(diffuse), _png(generate_normal_map(diffuse)), *diffuse.size)
    # The game renders its procedural asset directly in greybox builds. Direct
    # HTTP consumers also get a valid texture pair until artists drop in the PNG.
    diffuse = Image.new("RGBA", (64, 64))
    tint = tuple(100 + b // 2 for b in hashlib.sha1(asset.encode()).digest()[:3])
    draw = ImageDraw.Draw(diffuse)
    draw.polygon(((32, 4), (57, 31), (32, 60), (7, 31)), fill=(38, 32, 55))
    draw.polygon(((32, 8), (52, 31), (32, 53), (12, 31)), fill=tint)
    draw.line(((18, 31), (32, 15), (40, 24)), fill=(255, 242, 200), width=2)
    normal = Image.new("RGBA", diffuse.size, (128, 128, 255, 255))
    normal.putalpha(diffuse.getchannel("A"))
    return SpritePair(_png(diffuse), _png(normal), *diffuse.size)


def _atomic_write(path, data):
    fd, filename = tempfile.mkstemp(dir=path.parent)
    temp_path = Path(filename)
    try:
        with os.fdopen(fd, "wb") as temp:
            temp.write(data)
        os.replace(temp_path, path)
    finally:
        temp_path.unlink(missing_ok=True)


class SpritePipeline:
    def __init__(self, generate_image=None, cache_dir=None, hero_path=None, validate_sprite=None):
        self.generate_image = generate_image
        self.validate_sprite = validate_sprite
        self.cache_dir = Path(cache_dir) if cache_dir else ROOT / "cache" / "sprites"
        self.hero_path = Path(hero_path) if hero_path else ROOT / "assets" / "sprites" / "pudu_hero.png"
        self.executor = ThreadPoolExecutor(max_workers=3, thread_name_prefix="pudu-sprite")
        self.lock = threading.Lock()
        self.cache = OrderedDict()
        self.aliases = OrderedDict()
        self.jobs = OrderedDict()

    def close(self):
        self.executor.shutdown(wait=True, cancel_futures=True)

    @property
    def available(self):
        return IMAGING_AVAILABLE and self.generate_image is not None

    @property
    def cache_size(self):
        with self.lock:
            return len(self.cache)

    @staticmethod
    def _variant(source, purple, dim):
        slug = re.sub("[^a-z0-9]+", "-", source)[:38].strip("-") or "sprite"
        digest = hashlib.sha1(f"v1|{source}|{int(purple)}|{dim}".encode("utf-8")).hexdigest()
        return f"{slug}_{digest}"

    def _remember(self, key, pair):
        with self.lock:
            self.cache[key] = pair
            self.cache.move_to_end(key)
            if len(self.cache) > 12:
                self.cache.popitem(last=False)

    def _lookup(self, key):
        with self.lock:
            if key in self.cache:
                self.cache.move_to_end(key)
                return self.cache[key]
        try:
            diffuse = (self.cache_dir / f"{key}.png").read_bytes()
            normal = (self.cache_dir / f"{key}_n.png").read_bytes()
            # A cache from a previous launch must contain two complete PNGs.
            for data in (diffuse, normal):
                if not data.startswith(b"\x89PNG\r\n\x1a\n") or data[-8:-4] != b"IEND":
                    return None
            if diffuse[16:24] != normal[16:24]:
                return None
            pair = SpritePair(diffuse, normal, *struct.unpack(">II", diffuse[16:24]))
            self._remember(key, pair)
            return pair
        except (OSError, struct.error):
            return None

    def _store(self, key, pair):
        self._remember(key, pair)
        try:
            self.cache_dir.mkdir(parents=True, exist_ok=True)
            _atomic_write(self.cache_dir / f"{key}_n.png", pair.normal)
            _atomic_write(self.cache_dir / f"{key}.png", pair.diffuse)
        except OSError:
            pass  # Read-only installs retain the RAM cache.

    def _generate(self, source, description, purple, dim, live):
        ref = None if live else _reference(self.hero_path)
        subject = json.dumps(description, ensure_ascii=False)
        attempts = (
            (
                "Draw one pixel-art RPG sprite of the exact subject below (it may be in Spanish). "
                "Keep every specified feature. Show it facing right in full side view, with a bold outline, "
                "visible square pixels, limited 16-bit palette, no antialiasing. "
                "Leave a pure magenta #FF00FF margin on all sides. No shadow, scenery, text or border. "
                f"Subject: {subject}"
            ),
            (
                "Create a simple 16-bit game sprite, a single clearly recognizable silhouette "
                "matching the subject and its colors. Center it on a solid pure #FF00FF background. "
                f"No scenery, lettering or ground shadow. Draw exactly this subject: {subject}"
            ),
        )
        if ref:
            attempts = (attempts[0] + " Use the image only as a style reference.", attempts[1])
        max_tries = 2 if self.validate_sprite is not None else 1
        last_error = None
        for attempt_idx in range(max_tries):
            try:
                raw = self.generate_image(attempts[attempt_idx], ref if attempt_idx == 0 else None)
                if not isinstance(raw, bytes) or not 0 < len(raw) <= 16 * 1024 * 1024:
                    raise ValueError("El proveedor devolvió una imagen inválida.")
                pair = _prepare_sprite(raw, purple, dim)
            except (ValueError, OSError) as err:
                last_error = err
                continue
            if self.validate_sprite is not None:
                try:
                    ok, reason = self.validate_sprite(pair.diffuse, description)
                except Exception:
                    ok, reason = False, "No se pudo verificar el sprite."
                if not ok:
                    last_error = ValueError(reason or "Asset rechazado por Decisions API.")
                    continue
            self._store(self._variant(source, purple, dim), pair)
            return raw
        raise last_error or ValueError("Asset rechazado por control de calidad.")

    def _job(self, source, description, purple, dim, live=False):
        with self.lock:
            if source in self.jobs:
                future = self.jobs[source]
                if not future.done() or (not future.cancelled() and future.exception() is None):
                    self.jobs.move_to_end(source)
                    return future
                del self.jobs[source]
            if len(self.jobs) >= 6:
                oldest_done = next((key for key, future in self.jobs.items() if future.done()), None)
                if oldest_done is None:
                    return None
                del self.jobs[oldest_done]
            future = self.executor.submit(self._generate, source, description, purple, dim, live)
            self.jobs[source] = future
            return future

    def maybe_start_speculative_sprite(self, prompt, keep_purple=False, live=False):
        if not self.available or not isinstance(prompt, str):
            return None
        if live:
            prompt = live_prompt(prompt)
            if not prompt:
                return None
            source = f"live:{prompt}"
        else:
            source = " ".join(_words(prompt[:512]))
            if not source or match_exact_existing_sprite(prompt):
                return None
            self.bind_speculative_alias(prompt, prompt)
        purple = keep_purple is True or bool(PURPLE_WORDS.intersection(_words(prompt)))
        if self._lookup(self._variant(source, purple, 80)):
            return None
        return self._job(source, prompt[:512], purple, 80, live)

    def bind_speculative_alias(self, prompt, summon_name):
        if not isinstance(prompt, str) or not isinstance(summon_name, str):
            return
        alias = " ".join(_words(summon_name[:512]))
        source = " ".join(_words(prompt[:512]))
        if not alias or not source:
            return
        with self.lock:
            self.aliases[alias] = source
            self.aliases.move_to_end(alias)
            if len(self.aliases) > 64:
                self.aliases.popitem(last=False)

    @staticmethod
    def _response(pair, cached, start):
        return {"ok": True, "sprite_mode": "generate_live", "cached": cached, "width": pair.width, "height": pair.height,
                "latency_ms": round((time.monotonic() - start) * 1000),
                "diff_b64": base64.b64encode(pair.diffuse).decode("ascii"),
                "norm_b64": base64.b64encode(pair.normal).decode("ascii")}

    def get_sprite(self, payload, allow_generate=True):
        started = time.monotonic()
        if payload.get("live_sprite") is True:
            prompt = live_prompt(payload.get("original_prompt"))
            if not prompt:
                return {"ok": False, "error": "La invocación debe tener entre 2 y 12 caracteres."}
            purple = bool(PURPLE_WORDS.intersection(_words(prompt)))
            return self._get_generated(f"live:{prompt}", prompt, purple, 80, started, allow_generate, live=True)

        name = payload.get("name")
        if not isinstance(name, str) or not name.strip():
            return {"ok": False, "error": "Falta el nombre de la invocación."}
        name = name.strip()[:512]
        description = payload.get("sprite_prompt")
        description = description[:512] if isinstance(description, str) and description.strip() else name
        original = payload.get("original_prompt")
        label = " ".join(_words(name))
        with self.lock:
            source = self.aliases.get(label)
        if isinstance(original, str) and original.strip():
            source = " ".join(_words(original[:512]))
            description = original.strip()[:512]
        existing = match_exact_existing_sprite(source or name)
        if existing:
            # Direct /sprite calls can consume the same contract as generated art.
            # The game normally resolves this ID itself, including when Pillow is absent.
            result = {"ok": False, "error": "Usa el sprite incluido en el juego."}
            if IMAGING_AVAILABLE:
                try:
                    result = self._response(_bundled_sprite(existing), True, started)
                except (OSError, ValueError, TypeError):
                    pass
            return {**result, "sprite_mode": "existing", "existing_sprite": existing}
        source = source or " ".join(_words(description))
        purple = payload.get("keep_purple") is True or bool(PURPLE_WORDS.intersection(source.split()))
        try:
            dim = max(76, min(80, int(payload.get("target_dim", 80))))
        except (TypeError, ValueError, OverflowError):
            dim = 80
        return self._get_generated(source, description, purple, dim, started, allow_generate)

    def _get_generated(self, source, description, purple, dim, started, allow_generate, live=False):
        key = self._variant(source, purple, dim)
        pair = self._lookup(key)
        if pair:
            return self._response(pair, True, started)
        if not allow_generate or not self.available:
            return {"ok": False, "error": "Generación en vivo desactivada."}
        try:
            future = self._job(source, description, purple, dim, live)
            if future is None:
                return {"ok": False, "error": "Generador ocupado."}
            raw = future.result(timeout=25)
            pair = self._lookup(key)
            if pair is None:  # Same source, different size or Stage 1 color hint.
                pair = _prepare_sprite(raw, purple, dim)
                self._store(key, pair)
            return self._response(pair, False, started)
        except Exception:
            # The combat turn has already resolved. Never expose provider/auth details.
            return {"ok": False, "error": "Sprite en vivo no disponible."}
