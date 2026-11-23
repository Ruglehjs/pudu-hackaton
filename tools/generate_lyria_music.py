"""Google Lyria 3 Music & Jingle Generator + Seamless Loop Processor for Pudú Fantasy.

Uses the Gemini API (`lyria-3-clip-preview`) via GEMINI_API_KEY from `.env`,
archives raw outputs in `assets/audio/lyria_raw/` (excluded from .exe builds),
post-processes tracks with numpy + ffmpeg (via imageio-ffmpeg) into:
  - 8 seamless, beat-aligned, loudness-balanced `.ogg` BGM loops (4 biomes + 4 bosses)
  - 2 clean `.ogg` non-looping themes (victory & defeat)
  - 4 crisp musical jingles trimmed from Lyria 3 openings (encounter, restoration,
    completo pickup, critical hit) with instant-attack transient polish.

Also writes `assets/audio/tracks.json` with exact measured BPM & beat count so
`beat_sync.lua` locks tightly to every Lyria track without drift.

Usage:
    python tools/generate_lyria_music.py [--force] [--only bgm_overworld_desierto ...]
"""

from __future__ import annotations

import argparse
import base64
import json
import math
import os
import subprocess
import time
import urllib.error
import urllib.request
import wave
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import imageio_ffmpeg
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets" / "audio"
RAW_DIR = OUT_DIR / "lyria_raw"
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
MODEL = "lyria-3-clip-preview"
API_URL = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent"
SR = 44100


BGM_SPECS = [
    {
        "track_id": "overworld_desierto",
        "filename": "bgm_overworld_desierto.ogg",
        "target_bpm": 116.0,
        "loop": True,
        "prompt": (
            "Instrumental video game overworld theme for the Atacama Desert in Chile, "
            "warm sunny HD-2D adventure RPG soundtrack, bright Andean charango strumming, "
            "expressive wooden quena flute lead melody, gentle bombo leguero drum pulse, "
            "acoustic guitar rhythm, uplifting exploration mood, clean studio mix, "
            "steady 116 BPM, loopable game background music, strictly instrumental, no vocals"
        ),
    },
    {
        "track_id": "overworld_costa",
        "filename": "bgm_overworld_costa.ogg",
        "target_bpm": 124.0,
        "loop": True,
        "prompt": (
            "Instrumental video game coastal port town overworld theme inspired by Valparaiso Chile, "
            "cheerful seaside JRPG adventure soundtrack, lively accordion lead melody, "
            "nylon acoustic guitar, playful marimba counter-melody, bouncy upright bass and "
            "light crisp percussion, sunny ocean breeze vibe, steady 124 BPM, "
            "loopable game background music, strictly instrumental, no vocals"
        ),
    },
    {
        "track_id": "overworld_montana",
        "filename": "bgm_overworld_montana.ogg",
        "target_bpm": 112.0,
        "loop": True,
        "prompt": (
            "Instrumental video game snowy high-mountain overworld theme for the Andes Cordillera, "
            "majestic bright HD-2D JRPG soundtrack like Pokemon and Octopath Traveler, "
            "soaring Andean pan flute zampona melody, sparkling harp arpeggios, crisp orchestral strings, "
            "light echoing drums, crisp alpine air adventure mood, steady 112 BPM, "
            "loopable game background music, strictly instrumental, no vocals"
        ),
    },
    {
        "track_id": "overworld_chiloe",
        "filename": "bgm_overworld_chiloe.ogg",
        "target_bpm": 110.0,
        "loop": True,
        "prompt": (
            "Instrumental video game enchanted southern forest overworld theme inspired by Chiloe Island Chile, "
            "mystical yet warm JRPG adventure soundtrack, rhythmic acoustic guitar, charming folklore accordion, "
            "airy wooden flute melody, soft celesta glockenspiel sparkles, gentle steady wood percussion, "
            "misty green woods atmosphere, steady 110 BPM, loopable game background music, strictly instrumental, no vocals"
        ),
    },
    {
        "track_id": "battle_fardo",
        "filename": "bgm_battle_fardo.ogg",
        "target_bpm": 140.0,
        "loop": True,
        "prompt": (
            "High-energy instrumental Pokemon-style RPG battle theme with playful comedic flair, "
            "fast catchy brass trumpet and bright synth lead melody, driving slap bassline, "
            "snappy energetic drum kit with lively Andean charango rhythmic accents, upbeat heroic rival duel energy, "
            "crisp modern Nintendo orchestral-pop mix, steady 140 BPM, loopable video game battle music, "
            "strictly instrumental, no vocals"
        ),
    },
    {
        "track_id": "battle_mancha",
        "filename": "bgm_battle_mancha.ogg",
        "target_bpm": 134.0,
        "loop": True,
        "prompt": (
            "High-energy instrumental Pokemon-style villain team boss battle theme, "
            "groovy urgent funk-rock JRPG battle soundtrack, punchy synth brass stabs, "
            "slippery funky electric bassline, fast catchy lead melody with tense coastal accordion flourishes, "
            "driving crisp drums, mischievous harbor boss atmosphere, steady 134 BPM, "
            "loopable video game battle music, strictly instrumental, no vocals"
        ),
    },
    {
        "track_id": "battle_tempano",
        "filename": "bgm_battle_tempano.ogg",
        "target_bpm": 144.0,
        "loop": True,
        "prompt": (
            "High-energy instrumental Pokemon Gym Leader style RPG battle theme on an icy mountain summit, "
            "soaring heroic melody with bright trumpets, fast staccato orchestral strings, "
            "shimmering crystalline glockenspiel arpeggios, punchy rock bass and relentless crisp battle drums, "
            "exciting triumphant duel energy, steady 144 BPM, loopable video game battle music, "
            "strictly instrumental, no vocals"
        ),
    },
    {
        "track_id": "battle_brasa",
        "filename": "bgm_battle_brasa.ogg",
        "target_bpm": 150.0,
        "loop": True,
        "prompt": (
            "Epic final boss instrumental Pokemon Champion style RPG battle theme, "
            "blazing intense orchestral-rock soundtrack, heroic triumphant brass fanfare, "
            "fast electric guitar riffs, frantic virtuosic piano and string ostinatos, "
            "thunderous battle percussion, urgent fiery climax and heroic determination, "
            "steady 150 BPM, loopable video game final boss music, strictly instrumental, no vocals"
        ),
    },
    {
        "track_id": "victory",
        "filename": "bgm_victory.ogg",
        "target_bpm": 138.0,
        "loop": False,
        "max_sec": 12.0,
        "prompt": (
            "Triumphant celebratory instrumental Pokemon-style JRPG battle victory fanfare, "
            "bright heroic brass opening flourish right at zero seconds transitioning into a joyful "
            "bouncy celebratory orchestral-pop victory melody with glockenspiel sparkles and crisp snare drums, "
            "happy victorious ending, 138 BPM, strictly instrumental, no vocals"
        ),
    },
    {
        "track_id": "defeat",
        "filename": "bgm_defeat.ogg",
        "target_bpm": 100.0,
        "loop": False,
        "max_sec": 8.0,
        "prompt": (
            "Short gentle comedic-melancholic instrumental JRPG battle defeat jingle, "
            "sympathetic descending brass and woodwind melody starting immediately at zero seconds "
            "with soft pizzicato strings and warm acoustic guitar resolution, lighthearted setback mood, "
            "100 BPM, strictly instrumental, no vocals"
        ),
    },
]

JINGLE_SPECS = [
    {
        "name": "sfx_encounter_start",
        "filename": "sfx_encounter_start.wav",
        "max_sec": 1.65,
        "prompt": (
            "Urgent dramatic 2-second instrumental Pokemon-style wild battle encounter alert stinger, "
            "sharp electric synth and orchestral brass rising flash fanfare starting instantly at zero seconds, "
            "punchy arcade JRPG battle trigger, strictly instrumental, no vocals"
        ),
    },
    {
        "name": "sfx_biome_restored",
        "filename": "sfx_biome_restored.wav",
        "max_sec": 3.4,
        "prompt": (
            "Magical uplifting 3-second instrumental JRPG nature restoration fanfare chime, "
            "sparkling harp glissando, warm flute and bright major orchestral chord bloom starting instantly at zero seconds, "
            "celebrating healed nature, strictly instrumental, no vocals"
        ),
    },
    {
        "name": "sfx_completo_pickup",
        "filename": "sfx_completo_pickup.wav",
        "max_sec": 1.85,
        "prompt": (
            "Cheerful quirky 2-second instrumental Nintendo-style secret item pickup fanfare jingle, "
            "bright marimba arpeggio and playful brass major chord flourish starting instantly at zero seconds, "
            "fun treasure discovered chime, strictly instrumental, no vocals"
        ),
    },
    {
        "name": "sfx_crit_hit",
        "filename": "sfx_crit_hit.wav",
        "max_sec": 1.05,
        "prompt": (
            "Punchy explosive 1-second instrumental Pokemon-style critical hit musical impact stinger, "
            "sharp dramatic brass chord hit with bright sparkling chime burst right at zero seconds, "
            "strictly instrumental, no vocals"
        ),
    },
]


def load_api_key() -> str:
    if os.environ.get("GEMINI_API_KEY"):
        return os.environ["GEMINI_API_KEY"].strip()
    env_path = ROOT / ".env"
    if env_path.is_file():
        for line in env_path.read_text(encoding="utf-8-sig").splitlines():
            if "=" in line and not line.strip().startswith("#"):
                k, v = line.split("=", 1)
                if k.strip() == "GEMINI_API_KEY":
                    return v.strip().strip("\"'")
    raise RuntimeError("GEMINI_API_KEY not found in environment or .env")


def call_lyria(prompt: str, api_key: str, retries: int = 3) -> tuple[bytes, str]:
    payload = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"responseModalities": ["AUDIO"]},
    }
    raw_body = json.dumps(payload).encode("utf-8")
    last_err: Exception | None = None
    for attempt in range(1, retries + 1):
        req = urllib.request.Request(
            API_URL,
            data=raw_body,
            headers={"x-goog-api-key": api_key, "Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=90) as resp:
                data = json.loads(resp.read())
            for cand in data.get("candidates", []):
                for part in cand.get("content", {}).get("parts", []):
                    inline = part.get("inlineData")
                    if inline and inline.get("data"):
                        return base64.b64decode(inline["data"]), inline.get("mimeType", "audio/mpeg")
            raise RuntimeError(f"Lyria response contained no audio inlineData: {str(data)[:300]}")
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, RuntimeError) as exc:
            last_err = exc
            if isinstance(exc, urllib.error.HTTPError):
                err_txt = exc.read().decode("utf-8", "replace")[:260]
                last_err = RuntimeError(f"HTTP {exc.code}: {err_txt}")
            if attempt < retries:
                time.sleep(2.5 * attempt)
    raise RuntimeError(f"Lyria call failed after {retries} tries: {last_err}")


def decode_to_stereo_float(raw_path: Path, sr: int = SR) -> np.ndarray:
    """Decode any audio file (mp3/wav/ogg) via ffmpeg into float64 stereo [N, 2]."""
    cmd = [
        FFMPEG, "-v", "error", "-i", str(raw_path),
        "-ac", "2", "-ar", str(sr), "-f", "f32le", "pipe:1",
    ]
    res = subprocess.run(cmd, capture_output=True, check=True)
    pcm = np.frombuffer(res.stdout, dtype="<f4").astype(np.float64)
    return pcm.reshape(-1, 2)


def encode_ogg(stereo: np.ndarray, out_path: Path, sr: int = SR, quality: str = "5") -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.clip(stereo, -1.0, 1.0).astype("<f4").tobytes()
    cmd = [
        FFMPEG, "-y", "-v", "error",
        "-f", "f32le", "-ar", str(sr), "-ac", "2", "-i", "pipe:0",
        "-c:a", "libvorbis", "-q:a", quality, str(out_path),
    ]
    subprocess.run(cmd, input=pcm, check=True)


def write_wav_stereo(stereo: np.ndarray, out_path: Path, sr: int = SR) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    pcm = (np.clip(stereo, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(str(out_path), "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes(pcm.tobytes())


def trim_leading_silence(stereo: np.ndarray, thresh: float = 0.015, pad_sec: float = 0.004) -> np.ndarray:
    mono = np.max(np.abs(stereo), axis=1)
    idx = np.flatnonzero(mono > thresh)
    if len(idx) == 0:
        return stereo
    start = max(0, int(idx[0]) - int(pad_sec * SR))
    return stereo[start:]


def estimate_bpm(stereo: np.ndarray, hint_bpm: float) -> float:
    """Estimate actual BPM near hint_bpm using spectral-energy onset autocorrelation."""
    mono = np.mean(stereo, axis=1)
    hop = 512
    n_frames = len(mono) // hop
    if n_frames < 80:
        return hint_bpm
    frames = mono[: n_frames * hop].reshape(n_frames, hop)
    energy = np.sqrt(np.mean(frames * frames, axis=1))
    onset = np.maximum(0.0, np.diff(energy, prepend=energy[0]))
    onset -= np.mean(onset)
    ac = np.correlate(onset, onset, mode="full")[len(onset) - 1 :]
    fps = SR / hop
    lo_bpm = max(72.0, hint_bpm * 0.84)
    hi_bpm = min(180.0, hint_bpm * 1.18)
    min_lag = max(1, int(round(fps * 60.0 / hi_bpm)))
    max_lag = min(len(ac) - 1, int(round(fps * 60.0 / lo_bpm)))
    if max_lag <= min_lag:
        return hint_bpm
    best_lag = min_lag + int(np.argmax(ac[min_lag : max_lag + 1]))
    measured = fps * 60.0 / best_lag
    # If correlation peak is weak, stay with hint_bpm
    if ac[best_lag] <= 0.0:
        return hint_bpm
    return round(measured, 2)


def normalize_stereo(stereo: np.ndarray, target_rms: float = 0.19, peak_ceil: float = 0.90) -> np.ndarray:
    sig = stereo.copy()
    rms = float(np.sqrt(np.mean(sig * sig))) + 1e-9
    sig *= target_rms / rms
    sig = np.tanh(sig * 1.08) / math.tanh(1.08)
    peak = float(np.max(np.abs(sig))) + 1e-9
    if peak > peak_ceil:
        sig *= peak_ceil / peak
    return sig


def make_seamless_loop(stereo: np.ndarray, bpm: float) -> tuple[np.ndarray, int]:
    """Extract an integer-bar (multiple of 4 beats) loop with equal-power overlap crossfade."""
    sig = trim_leading_silence(stereo, thresh=0.018, pad_sec=0.005)
    sec_per_beat = 60.0 / bpm
    total_sec = len(sig) / SR
    # Reserve ~1.4s tail for overlap crossfade so loop seam is completely seamless!
    xfade_sec = min(1.4, max(0.6, 2.0 * sec_per_beat))
    usable_sec = max(4.0 * sec_per_beat, total_sec - xfade_sec - 0.3)
    bars = max(4, int(usable_sec / (4.0 * sec_per_beat)))
    beats = bars * 4
    loop_len = int(round(beats * sec_per_beat * SR))
    xfade_n = min(int(round(xfade_sec * SR)), max(1, len(sig) - loop_len))

    if xfade_n >= int(0.25 * SR) and loop_len + xfade_n <= len(sig):
        # Skip brief intro fade-in (0.2s) if plenty of audio exists so beat 0 hits strong
        offset = int(0.15 * SR) if (loop_len + xfade_n + int(0.15 * SR) <= len(sig)) else 0
        body = sig[offset : offset + loop_len].copy()
        tail = sig[offset + loop_len : offset + loop_len + xfade_n]
        t = np.linspace(0.0, 0.5 * math.pi, xfade_n)[:, None]
        # Equal-power blend: head fades in from tail so seam wraps invisibly!
        body[:xfade_n] = body[:xfade_n] * np.sin(t) + tail * np.cos(t)
        return body, beats

    # Fallback: exact loop_len with tiny edge smooth
    body = sig[: min(loop_len, len(sig))].copy()
    if len(body) < loop_len:
        body = np.pad(body, ((0, loop_len - len(body)), (0, 0)))
    edge = min(256, len(body) // 4)
    fade = np.linspace(0.0, 1.0, edge)[:, None]
    body[:edge] *= fade
    body[-edge:] *= fade[::-1]
    return body, beats


def process_bgm(spec: dict, api_key: str, force: bool) -> dict:
    tid = spec["track_id"]
    raw_mp3 = RAW_DIR / f"{tid}.mp3"
    if force or not raw_mp3.is_file() or raw_mp3.stat().st_size < 10000:
        audio_bytes, _ = call_lyria(spec["prompt"], api_key)
        raw_mp3.parent.mkdir(parents=True, exist_ok=True)
        raw_mp3.write_bytes(audio_bytes)

    stereo = decode_to_stereo_float(raw_mp3)
    if spec["loop"]:
        bpm = estimate_bpm(stereo, spec["target_bpm"])
        looped, beats = make_seamless_loop(stereo, bpm)
        final = normalize_stereo(looped, target_rms=0.19, peak_ceil=0.90)
    else:
        sig = trim_leading_silence(stereo, thresh=0.012, pad_sec=0.004)
        max_n = int(round(spec.get("max_sec", 10.0) * SR))
        if len(sig) > max_n:
            sig = sig[:max_n].copy()
        fade_out = min(len(sig), int(0.55 * SR))
        sig[-fade_out:] *= np.linspace(1.0, 0.0, fade_out)[:, None] ** 1.4
        bpm = spec["target_bpm"]
        beats = max(8, int(round((len(sig) / SR) * bpm / 60.0)))
        final = normalize_stereo(sig, target_rms=0.19, peak_ceil=0.90)

    out_path = OUT_DIR / spec["filename"]
    encode_ogg(final, out_path)
    return {
        "track_id": tid,
        "path": f"assets/audio/{spec['filename']}",
        "bpm": bpm,
        "beats": beats,
        "beatOffset": 0.0,
        "loop": spec["loop"],
        "dur": round(len(final) / SR, 3),
        "kb": round(out_path.stat().st_size / 1024.0, 1),
    }


def process_jingle(spec: dict, api_key: str, force: bool) -> dict:
    name = spec["name"]
    raw_mp3 = RAW_DIR / f"{name}.mp3"
    if force or not raw_mp3.is_file() or raw_mp3.stat().st_size < 8000:
        audio_bytes, _ = call_lyria(spec["prompt"], api_key)
        raw_mp3.parent.mkdir(parents=True, exist_ok=True)
        raw_mp3.write_bytes(audio_bytes)

    stereo = decode_to_stereo_float(raw_mp3)
    sig = trim_leading_silence(stereo, thresh=0.020, pad_sec=0.002)
    max_n = int(round(spec["max_sec"] * SR))
    if len(sig) > max_n:
        sig = sig[:max_n].copy()

    # Crisp instant attack (3ms) & clean smooth tail fade (180ms)
    fade_in = min(len(sig), int(0.003 * SR))
    fade_out = min(len(sig), int(0.22 * SR))
    sig[:fade_in] *= np.linspace(0.0, 1.0, fade_in)[:, None]
    sig[-fade_out:] *= np.linspace(1.0, 0.0, fade_out)[:, None] ** 1.5
    final = normalize_stereo(sig, target_rms=0.22, peak_ceil=0.92)

    out_path = OUT_DIR / spec["filename"]
    write_wav_stereo(final, out_path)
    return {
        "name": name,
        "dur": round(len(final) / SR, 3),
        "kb": round(out_path.stat().st_size / 1024.0, 1),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true", help="Regenerate even if cached in lyria_raw/")
    parser.add_argument("--only", nargs="*", default=None, help="Only process specific track_ids or jingle names")
    args = parser.parse_args()

    api_key = load_api_key()
    only = set(args.only) if args.only else None

    bgm_jobs = [s for s in BGM_SPECS if not only or s["track_id"] in only]
    jingle_jobs = [s for s in JINGLE_SPECS if not only or s["name"] in only]

    print(f"Generating {len(bgm_jobs)} BGM + {len(jingle_jobs)} jingles with Google Lyria ({MODEL})...")
    bgm_results: dict[str, dict] = {}
    jingle_results: list[dict] = []

    with ThreadPoolExecutor(max_workers=4) as pool:
        futs = {}
        for spec in bgm_jobs:
            futs[pool.submit(process_bgm, spec, api_key, args.force)] = ("bgm", spec["track_id"])
        for spec in jingle_jobs:
            futs[pool.submit(process_jingle, spec, api_key, args.force)] = ("jingle", spec["name"])

        for fut in as_completed(futs):
            kind, ident = futs[fut]
            res = fut.result()
            if kind == "bgm":
                bgm_results[ident] = res
                print(
                    f"  [LYRIA BGM]    {ident:20s} -> {res['path']:38s} "
                    f"bpm={res['bpm']:6.2f} beats={res['beats']:2d} dur={res['dur']:5.2f}s ({res['kb']} KB)"
                )
            else:
                jingle_results.append(res)
                print(f"  [LYRIA JINGLE] {ident:20s} -> dur={res['dur']:4.2f}s ({res['kb']} KB)")

    # Write assets/audio/tracks.json so audio.lua picks up exact measured BPM/beats automatically
    tracks_json_path = OUT_DIR / "tracks.json"
    existing = {}
    if tracks_json_path.is_file():
        try:
            existing = json.loads(tracks_json_path.read_text(encoding="utf-8"))
        except Exception:
            existing = {}

    for tid, info in bgm_results.items():
        existing[tid] = {
            "path": info["path"],
            "bpm": info["bpm"],
            "beats": info["beats"],
            "beatOffset": info["beatOffset"],
            "loop": info["loop"],
        }
    # Keep aliases aligned
    alias_map = {
        "overworld": "overworld_desierto",
        "overworld_bosque": "overworld_chiloe",
        "user_battle": "battle_fardo",
        "plaza": "battle_fardo",
        "superstar": "battle_mancha",
        "boss": "battle_brasa",
        "battle_pila_ropa": "battle_fardo",
        "battle_gaviota": "battle_mancha",
        "battle_puma": "battle_brasa",
        "battle_caleuche": "battle_tempano",
    }
    for alias, target in alias_map.items():
        if target in existing:
            existing[alias] = dict(existing[target])

    tracks_json_path.write_text(json.dumps(existing, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Saved exact Lyria track metadata to {tracks_json_path}")


if __name__ == "__main__":
    main()
