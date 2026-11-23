"""HD-2D Modern Pokémon-inspired Sound Effects Synthesizer (44.1 kHz Stereo) for Pudú Fantasy.

Generates ~68 rich, modern game sound effects with FFT-domain resonant filtering,
FM bells, layered sub-bass impacts, physical noise shaping, and clean stereo room reverb:
  - 26 base SFX (skipping the 4 Lyria musical jingles when already present unless --overwrite-jingles)
  - 8 elemental stage states (mojado, congelado, caliente, enjabonado, aceitoso, oscuro, ruidoso, pegajoso)
  - 6 Pokémon-style super-combo spectacles
  - 8 enemy counterattack effects
  - Dramatic VS presentation (sfx_versus_intro, sfx_versus_impact), scene transition swoosh,
    Osu! ritual feedback (sfx_osu_hit, sfx_osu_slider, sfx_ritual_wave), mountain footsteps
    (sfx_step_stone), UI polish, truck arrival, and fallbacks for all 4 Lyria jingles.

Usage:
    python tools/generate_pokemon_sfx.py [--overwrite-jingles]
"""

from __future__ import annotations

import argparse
import math
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets" / "audio"
SR = 44100

LYRIA_JINGLES = {
    "sfx_encounter_start.wav",
    "sfx_biome_restored.wav",
    "sfx_completo_pickup.wav",
    "sfx_crit_hit.wav",
}


# ---------------------------------------------------------------------------
# Fast Vectorized Modern DSP Building Blocks (44.1 kHz Stereo)
# ---------------------------------------------------------------------------

def midi_hz(m: float) -> float:
    return 440.0 * (2.0 ** ((m - 69.0) / 12.0))


def phase_of(freq: np.ndarray | float, n: int) -> np.ndarray:
    if np.isscalar(freq):
        return 2.0 * math.pi * float(freq) * np.arange(n, dtype=np.float64) / SR
    return 2.0 * math.pi * np.cumsum(np.asarray(freq, dtype=np.float64) / SR)


def sine(freq: np.ndarray | float, n: int) -> np.ndarray:
    return np.sin(phase_of(freq, n))


def warm_saw(freq: np.ndarray | float, n: int, harmonics: int = 12) -> np.ndarray:
    ph = phase_of(freq, n)
    out = np.zeros(n, dtype=np.float64)
    fmax = float(np.max(freq)) if not np.isscalar(freq) else float(freq)
    kmax = min(harmonics, max(1, int((SR * 0.42) / max(20.0, fmax))))
    for k in range(1, kmax + 1):
        out += ((-1.0) ** (k + 1) / (k ** 1.15)) * np.sin(k * ph)
    return out * 0.65


def warm_pulse(freq: np.ndarray | float, n: int, duty: float = 0.25, harmonics: int = 10) -> np.ndarray:
    ph = phase_of(freq, n)
    out = np.zeros(n, dtype=np.float64)
    fmax = float(np.max(freq)) if not np.isscalar(freq) else float(freq)
    kmax = min(harmonics, max(1, int((SR * 0.42) / max(20.0, fmax))))
    for k in range(1, kmax + 1):
        amp = (2.0 / (k * math.pi)) * math.sin(math.pi * k * duty) / (1.0 + 0.08 * k)
        out += amp * np.cos(k * ph)
    return out


def white_noise(n: int, seed: int = 1) -> np.ndarray:
    return np.random.default_rng(seed).standard_normal(n)


def spectral_filter(x: np.ndarray, lo_hz: float = 0.0, hi_hz: float = SR * 0.49, slope: float = 2.0) -> np.ndarray:
    """Zero-phase smooth resonant FFT bandpass/lowpass/highpass filter."""
    n = len(x)
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    gain = np.ones_like(freqs)
    if lo_hz > 1.0:
        gain *= 1.0 / np.sqrt(1.0 + (lo_hz / np.maximum(freqs, 1e-3)) ** (2.0 * slope))
    if hi_hz < SR * 0.48:
        gain *= 1.0 / np.sqrt(1.0 + (freqs / max(20.0, hi_hz)) ** (2.0 * slope))
    return np.fft.irfft(spec * gain, n=n)


def env_exp(n: int, attack: float = 0.003, decay: float = 9.0) -> np.ndarray:
    t = np.arange(n, dtype=np.float64) / SR
    a = min(n, max(1, int(attack * SR)))
    e = np.exp(-t * decay)
    e[:a] *= np.linspace(0.0, 1.0, a)
    tail = min(n, max(1, int(0.015 * SR)))
    e[-tail:] *= np.linspace(1.0, 0.0, tail)
    return e


def env_adsr(n: int, a: float = 0.005, d: float = 0.07, s: float = 0.65, r: float = 0.05) -> np.ndarray:
    e = np.full(n, s, dtype=np.float64)
    na = min(n, max(1, int(a * SR)))
    nd = min(n - na, max(0, int(d * SR)))
    nr = min(n, max(1, int(r * SR)))
    e[:na] = np.linspace(0.0, 1.0, na, endpoint=False)
    if nd > 0:
        e[na : na + nd] = np.linspace(1.0, s, nd, endpoint=False)
    e[-nr:] *= np.linspace(1.0, 0.0, nr)
    return e


def fm_bell(midi: float, dur: float, mod_ratio: float = 2.0, mod_index: float = 1.6, decay: float = 7.5) -> np.ndarray:
    """Lush crystalline FM chime / celesta bell (Pokémon menu, heal, ice, Osu)."""
    n = max(64, int(dur * SR))
    t = np.arange(n, dtype=np.float64) / SR
    fc = midi_hz(midi)
    mod = mod_index * np.exp(-t * (decay * 1.6)) * np.sin(2.0 * math.pi * (fc * mod_ratio) * t)
    car = np.sin(2.0 * math.pi * fc * t + mod)
    shimmer = 0.22 * np.sin(2.0 * math.pi * (fc * 3.0) * t) * np.exp(-t * (decay * 2.2))
    return (car + shimmer) * env_exp(n, attack=0.002, decay=decay)


def brass_stab(midis: list[float], dur: float) -> np.ndarray:
    """Warm modern Pokémon brass chord stab."""
    n = max(64, int(dur * SR))
    t = np.arange(n, dtype=np.float64) / SR
    out = np.zeros(n, dtype=np.float64)
    scoop = np.ones(n, dtype=np.float64)
    sc = min(n, int(0.022 * SR))
    scoop[:sc] = np.linspace(0.97, 1.0, sc)
    for m in midis:
        f = midi_hz(m) * scoop
        out += 0.55 * warm_saw(f, n, 12) + 0.45 * warm_pulse(f * 1.002, n, 0.30, 8)
    out = spectral_filter(out, lo_hz=90.0, hi_hz=6800.0, slope=1.8)
    return out / max(1, len(midis)) * env_adsr(n, 0.008, 0.06, 0.72, min(0.09, dur * 0.35))


def stereo_reverb(mono: np.ndarray, wet: float = 0.24, tail_sec: float = 0.16) -> np.ndarray:
    """Clean stereo early-reflection + diffuse room sheen for HD-2D polish."""
    pad = int(tail_sec * SR)
    x = np.pad(mono, (0, pad))
    left = x.copy()
    right = x.copy()
    taps_l = [(0.013, 0.40), (0.029, 0.28), (0.053, 0.19), (0.089, 0.12)]
    taps_r = [(0.017, 0.38), (0.037, 0.27), (0.067, 0.18), (0.107, 0.11)]
    for delay_s, g in taps_l:
        d = int(delay_s * SR)
        if d < len(x):
            left[d:] += x[:-d] * (g * wet)
    for delay_s, g in taps_r:
        d = int(delay_s * SR)
        if d < len(x):
            right[d:] += x[:-d] * (g * wet)
    left = spectral_filter(left, hi_hz=11000.0, slope=1.5)
    right = spectral_filter(right, hi_hz=11000.0, slope=1.5)
    return np.stack([left, right], axis=1)


def place(buf: np.ndarray, t_sec: float, seg: np.ndarray, gain: float = 1.0) -> None:
    i0 = int(round(t_sec * SR))
    if i0 < 0 or i0 >= len(buf):
        return
    i1 = min(len(buf), i0 + len(seg))
    buf[i0:i1] += seg[: i1 - i0] * gain


def arp_bells(midis: list[float], step: float = 0.048, dur: float = 0.28, decay: float = 7.0, mod_idx: float = 1.4) -> np.ndarray:
    total = int((len(midis) * step + dur) * SR)
    buf = np.zeros(total, dtype=np.float64)
    for i, m in enumerate(midis):
        place(buf, i * step, fm_bell(m, dur, 2.0, mod_idx, decay), 0.72)
    return buf


def punch_hit(sub_hi: float = 175.0, sub_lo: float = 40.0, dur: float = 0.26, seed: int = 1) -> np.ndarray:
    """Modern Pokémon physical attack impact: crisp transient crack + deep sub thump."""
    n = int(dur * SR)
    t = np.arange(n, dtype=np.float64) / SR
    sub_f = sub_lo + (sub_hi - sub_lo) * np.exp(-t * 32.0)
    sub = sine(sub_f, n) * np.exp(-t * 14.0)
    crack = spectral_filter(white_noise(n, seed), 700.0, 5800.0) * np.exp(-t * 38.0)
    body = spectral_filter(white_noise(n, seed + 50), 140.0, 1200.0) * np.exp(-t * 19.0)
    return 0.78 * sub + 0.65 * crack + 0.42 * body


def master_sfx(sig: np.ndarray, peak_target: float = 0.86, wet: float = 0.22, tail_sec: float = 0.14) -> np.ndarray:
    if sig.ndim == 1:
        stereo = stereo_reverb(sig, wet=wet, tail_sec=tail_sec) if wet > 0 else np.stack([sig, sig], axis=1)
    else:
        stereo = sig.copy()
    n = len(stereo)
    fi = min(n, max(1, int(0.002 * SR)))
    fo = min(n, max(1, int(0.018 * SR)))
    stereo[:fi] *= np.linspace(0.0, 1.0, fi)[:, None]
    stereo[-fo:] *= np.linspace(1.0, 0.0, fo)[:, None]
    stereo = np.tanh(stereo * 1.12) / math.tanh(1.12)
    peak = float(np.max(np.abs(stereo))) + 1e-9
    return stereo * (peak_target / peak)


def write_wav(path: Path, stereo: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = (np.clip(stereo, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(pcm.tobytes())


# ---------------------------------------------------------------------------
# All Modern HD-2D Pokémon-Style SFX Recipes
# ---------------------------------------------------------------------------

def build_sfx_catalog() -> dict[str, np.ndarray]:
    s: dict[str, np.ndarray] = {}

    # === 1. NEW POKEMON-STYLE SCENE & VS PRESENTATION ===

    # sfx_versus_intro: dramatic rising orchestral-synth tension sweep into VS slam
    n = int(0.62 * SR)
    t = np.arange(n) / SR
    whoosh = spectral_filter(white_noise(n, 701), 280.0, 4200.0) * (t / 0.62) ** 1.4
    riser_f = 180.0 * (2.0 ** (t * 3.8))
    riser = (0.55 * warm_saw(riser_f, n, 10) + 0.45 * sine(riser_f * 0.5, n)) * (t / 0.62) ** 1.2
    buf = 0.55 * whoosh + 0.65 * riser
    for i in range(6):
        place(buf, 0.05 + i * 0.085, punch_hit(200 + i * 25, 65, 0.09, 710 + i), 0.35 + i * 0.08)
    s["sfx_versus_intro.wav"] = master_sfx(buf, 0.88, wet=0.28, tail_sec=0.14)

    # sfx_versus_impact: thunderous Pokémon/Smash VS clash!
    buf = np.zeros(int(0.85 * SR))
    place(buf, 0.0, punch_hit(240.0, 34.0, 0.48, 720), 1.0)
    # Metallic sword/shield clang + heroic brass impact chord
    n_cl = int(0.45 * SR)
    t_cl = np.arange(n_cl) / SR
    clang = (
        0.5 * sine(1180.0, n_cl) + 0.4 * sine(1890.0, n_cl) + 0.35 * sine(2860.0, n_cl)
        + 0.45 * spectral_filter(white_noise(n_cl, 721), 2400.0, 9500.0) * np.exp(-t_cl * 16.0)
    ) * np.exp(-t_cl * 8.5)
    place(buf, 0.005, clang, 0.62)
    place(buf, 0.01, brass_stab([57, 64, 69, 76], 0.46), 0.72)
    s["sfx_versus_impact.wav"] = master_sfx(buf, 0.92, wet=0.35, tail_sec=0.25)

    # sfx_scene_transition: sleek Pokémon screen-wipe swoosh
    n = int(0.50 * SR)
    t = np.arange(n) / SR
    arch = np.sin(math.pi * t / 0.50) ** 0.85
    sw = spectral_filter(white_noise(n, 730), 400.0, 5200.0) * arch * 0.65
    tone = warm_pulse(280.0 + 780.0 * (t / 0.50) ** 1.2, n, 0.30, 8) * arch * 0.42
    buf = sw + tone
    place(buf, 0.06, arp_bells([72, 79, 84], 0.055, 0.22, 9.0), 0.45)
    s["sfx_scene_transition.wav"] = master_sfx(buf, 0.84, wet=0.28, tail_sec=0.16)

    # sfx_battle_enter: energetic Pokémon arena dash-in
    n = int(0.38 * SR)
    t = np.arange(n) / SR
    arch = np.sin(math.pi * t / 0.38)
    buf = spectral_filter(white_noise(n, 735), 500.0, 4600.0) * arch * 0.55
    place(buf, 0.0, arp_bells([67, 72, 76, 79], 0.048, 0.18, 9.5), 0.70)
    s["sfx_battle_enter.wav"] = master_sfx(buf, 0.82, wet=0.22, tail_sec=0.12)

    # === 2. NEW PR #5 MECHANICS (OSU! RITUAL, MOUNTAIN STEPS, RESTORATION/COMPLETO FALLBACKS) ===

    # sfx_osu_hit: super-satisfying glassy Osu/Pokémon tap chime
    buf = fm_bell(81, 0.18, 2.0, 1.3, 14.0)
    place(buf, 0.0, punch_hit(340, 120, 0.05, 740), 0.28)
    s["sfx_osu_hit.wav"] = master_sfx(buf, 0.80, wet=0.20, tail_sec=0.08)

    # sfx_osu_slider: shimmering magical ribbon glide
    buf = arp_bells([76, 79, 83, 88, 91], 0.036, 0.22, 8.5, 1.2)
    s["sfx_osu_slider.wav"] = master_sfx(buf, 0.82, wet=0.30, tail_sec=0.15)

    # sfx_ritual_wave: exciting extra-wave power-up chime
    buf = arp_bells([72, 76, 79, 84, 88], 0.045, 0.26, 7.5, 1.5)
    place(buf, 0.18, brass_stab([72, 79, 84], 0.22), 0.35)
    s["sfx_ritual_wave.wav"] = master_sfx(buf, 0.84, wet=0.28, tail_sec=0.16)

    # sfx_step_stone: crisp Andean gravel / snow-crust footstep
    n = int(0.085 * SR)
    t = np.arange(n) / SR
    crunch = spectral_filter(white_noise(n, 745), 900.0, 5600.0) * np.exp(-t * 42.0)
    tap = sine(180.0 * np.exp(-t * 28.0) + 75.0, n) * np.exp(-t * 48.0)
    s["sfx_step_stone.wav"] = master_sfx(0.70 * crunch + 0.35 * tap, 0.60, wet=0.12, tail_sec=0.04)

    # Fallback jingles (skipped if Lyria already wrote them)
    buf = np.zeros(int(1.05 * SR))
    place(buf, 0.0, punch_hit(220, 42, 0.28, 101), 0.85)
    place(buf, 0.04, brass_stab([64, 71, 76], 0.24), 0.65)
    place(buf, 0.24, brass_stab([67, 74, 79], 0.24), 0.70)
    place(buf, 0.44, brass_stab([71, 76, 83], 0.48), 0.82)
    s["sfx_encounter_start.wav"] = master_sfx(buf, 0.90, wet=0.30, tail_sec=0.20)

    s["sfx_biome_restored.wav"] = master_sfx(
        arp_bells([65, 69, 72, 76, 77, 81, 84, 89], 0.075, 0.55, 4.5, 1.2), 0.86, wet=0.40, tail_sec=0.30
    )
    s["sfx_completo_pickup.wav"] = master_sfx(
        arp_bells([72, 76, 79, 84, 88], 0.055, 0.34, 6.5, 1.4), 0.85, wet=0.28, tail_sec=0.16
    )
    buf_cr = np.zeros(int(0.55 * SR))
    place(buf_cr, 0.0, punch_hit(240, 38, 0.32, 149), 0.95)
    place(buf_cr, 0.015, arp_bells([76, 83, 88, 95], 0.036, 0.26, 7.5), 0.80)
    s["sfx_crit_hit.wav"] = master_sfx(buf_cr, 0.90, wet=0.28, tail_sec=0.16)

    # === 3. UPGRADED 26 BASE SFX (HD-2D POKEMON STYLE) ===

    # sfx_rain_pour
    n = int(0.85 * SR)
    t = np.arange(n) / SR
    rain = spectral_filter(white_noise(n, 202), 850.0, 6200.0) * (np.sin(math.pi * t / 0.85) ** 0.55)
    buf = rain * 0.62
    for i, dt in enumerate([0.07, 0.16, 0.27, 0.39, 0.51, 0.64]):
        place(buf, dt, fm_bell(80 + (i * 5) % 12, 0.10, 1.5, 0.8, 18.0), 0.28)
    s["sfx_rain_pour.wav"] = master_sfx(buf, 0.80, wet=0.28, tail_sec=0.14)

    # sfx_splat
    n = int(0.36 * SR)
    t = np.arange(n) / SR
    f = 380.0 * np.exp(-t * 14.0) + 70.0 + 48.0 * np.sin(2 * math.pi * 42 * t)
    sig = 0.55 * warm_pulse(f, n, 0.35, 8) + 0.60 * spectral_filter(white_noise(n, 203), 180.0, 2100.0)
    s["sfx_splat.wav"] = master_sfx(sig * env_exp(n, 0.004, 10.0), 0.84, wet=0.18, tail_sec=0.08)

    # sfx_boing
    n = int(0.42 * SR)
    t = np.arange(n) / SR
    f = (165.0 + 410.0 * (1.0 - np.exp(-t * 10.5))) * (1.0 + 0.08 * np.sin(2 * math.pi * 22.0 * t))
    sig = 0.55 * warm_pulse(f, n, 0.30, 8) + 0.50 * sine(f, n)
    s["sfx_boing.wav"] = master_sfx(sig * env_exp(n, 0.003, 5.0), 0.84, wet=0.22, tail_sec=0.10)

    # sfx_laugh
    buf = np.zeros(int(0.62 * SR))
    for i, m in enumerate([74, 72, 69, 67, 64]):
        nn = int(0.095 * SR)
        tt = np.arange(nn) / SR
        ff = midi_hz(m) * (1.08 - 0.16 * tt / 0.095)
        place(buf, i * 0.105, (0.65 * warm_saw(ff, nn, 8) + 0.35 * sine(ff, nn)) * env_exp(nn, 0.004, 14.0), 0.80)
    s["sfx_laugh.wav"] = master_sfx(buf, 0.84, wet=0.22, tail_sec=0.10)

    # sfx_camera_flash
    buf = np.zeros(int(0.40 * SR))
    place(buf, 0.0, punch_hit(420, 140, 0.06, 206), 0.55)
    n2 = int(0.32 * SR)
    t2 = np.arange(n2) / SR
    sh = spectral_filter(white_noise(n2, 207), 2600.0, 12000.0) * np.exp(-t2 * 11.0)
    place(buf, 0.025, sh, 0.58)
    place(buf, 0.025, fm_bell(93, 0.28, 2.76, 2.0, 11.0), 0.48)
    s["sfx_camera_flash.wav"] = master_sfx(buf, 0.86, wet=0.30, tail_sec=0.15)

    # sfx_horn
    buf = np.zeros(int(0.48 * SR))
    place(buf, 0.0, brass_stab([62, 65, 69], 0.17), 0.85)
    place(buf, 0.21, brass_stab([62, 65, 69], 0.23), 0.90)
    s["sfx_horn.wav"] = master_sfx(buf, 0.85, wet=0.24, tail_sec=0.12)

    # sfx_rimshot
    buf = np.zeros(int(0.62 * SR))
    place(buf, 0.00, punch_hit(240, 95, 0.12, 208), 0.85)
    place(buf, 0.13, punch_hit(155, 52, 0.16, 209), 0.82)
    nc = int(0.34 * SR)
    tc = np.arange(nc) / SR
    cym = spectral_filter(white_noise(nc, 210), 3400.0, 13000.0) * np.exp(-tc * 9.5)
    place(buf, 0.27, cym, 0.82)
    s["sfx_rimshot.wav"] = master_sfx(buf, 0.86, wet=0.24, tail_sec=0.12)

    # sfx_meow_scared
    n = int(0.46 * SR)
    t = np.arange(n) / SR
    f = 600.0 + 760.0 * np.sin(math.pi * np.clip(t / 0.22, 0, 1)) - 390.0 * np.clip((t - 0.18) / 0.28, 0, 1)
    f *= 1.0 + 0.035 * np.sin(2 * math.pi * 26.0 * t)
    sig = spectral_filter(0.60 * warm_saw(f, n, 10) + 0.40 * warm_pulse(f, n, 0.22, 8), 350.0, 5200.0)
    s["sfx_meow_scared.wav"] = master_sfx(sig * env_adsr(n, 0.015, 0.08, 0.72, 0.10), 0.84, wet=0.24, tail_sec=0.12)

    # sfx_seagull
    buf = np.zeros(int(0.56 * SR))
    for st, dur, base in [(0.0, 0.22, 900.0), (0.26, 0.25, 980.0)]:
        nn = int(dur * SR)
        tt = np.arange(nn) / SR
        f = base + 320.0 * np.sin(math.pi * tt / dur) - 240.0 * (tt / dur)
        sig = spectral_filter(0.70 * warm_pulse(f, nn, 0.18, 8) + 0.25 * white_noise(nn, 211), 650.0, 4800.0)
        place(buf, st, sig * env_adsr(nn, 0.015, 0.05, 0.70, 0.06), 0.85)
    s["sfx_seagull.wav"] = master_sfx(buf, 0.84, wet=0.28, tail_sec=0.14)

    # sfx_cry_wah
    buf = np.zeros(int(0.72 * SR))
    for st, dur, hi, lo in [(0.0, 0.25, 440.0, 392.0), (0.28, 0.40, 370.0, 305.0)]:
        nn = int(dur * SR)
        tt = np.arange(nn) / SR
        f = np.linspace(hi, lo, nn) * (1.0 + 0.025 * np.sin(2 * math.pi * 6.5 * tt))
        sig = spectral_filter(0.60 * warm_saw(f, nn, 10) + 0.40 * sine(f, nn), 180.0, 3200.0)
        place(buf, st, sig * env_adsr(nn, 0.018, 0.06, 0.74, 0.09), 0.85)
    s["sfx_cry_wah.wav"] = master_sfx(buf, 0.84, wet=0.26, tail_sec=0.14)

    # water_rush
    n = int(0.68 * SR)
    t = np.arange(n) / SR
    buf = spectral_filter(white_noise(n, 212), 220.0, 3200.0) * (np.sin(math.pi * t / 0.68) ** 0.65) * 0.78
    for i, dt in enumerate([0.08, 0.16, 0.25, 0.35, 0.46]):
        nn = int(0.08 * SR)
        tt = np.arange(nn) / SR
        place(buf, dt, sine((420 + i * 95) * (1.0 + 0.72 * tt / 0.08), nn) * env_exp(nn, 0.002, 22.0), 0.34)
    s["water_rush.wav"] = master_sfx(buf, 0.86, wet=0.28, tail_sec=0.16)

    # bash_impact (classic Pokémon physical super-punch)
    buf = np.zeros(int(0.34 * SR))
    place(buf, 0.0, punch_hit(210.0, 38.0, 0.30, 213), 1.0)
    place(buf, 0.01, fm_bell(69, 0.16, 1.41, 2.2, 16.0), 0.36)
    s["bash_impact.wav"] = master_sfx(buf, 0.90, wet=0.22, tail_sec=0.12)

    # stomp
    n = int(0.42 * SR)
    t = np.arange(n) / SR
    sub = sine(135.0 * np.exp(-t * 13.0) + 32.0, n) * np.exp(-t * 7.5)
    rumble = spectral_filter(white_noise(n, 214), 50.0, 820.0) * np.exp(-t * 10.5) * 0.65
    s["stomp.wav"] = master_sfx(sub + rumble, 0.90, wet=0.22, tail_sec=0.14)

    # dog_bark
    buf = np.zeros(int(0.44 * SR))
    for st, base in [(0.0, 320.0), (0.20, 370.0)]:
        nn = int(0.15 * SR)
        tt = np.arange(nn) / SR
        f = base * (1.28 - 0.58 * tt / 0.15)
        sig = spectral_filter(0.68 * warm_saw(f, nn, 10) + 0.35 * white_noise(nn, 215), 220.0, 2400.0)
        place(buf, st, sig * env_exp(nn, 0.004, 14.0), 0.90)
    s["dog_bark.wav"] = master_sfx(buf, 0.85, wet=0.20, tail_sec=0.10)

    # chime_1, chime_2, chime_3 (lush Pokémon crystal ritual chimes)
    s["chime_1.wav"] = master_sfx(fm_bell(72, 0.28, 2.0, 1.2, 8.5), 0.82, wet=0.28, tail_sec=0.14)
    s["chime_2.wav"] = master_sfx(fm_bell(76, 0.28, 2.0, 1.2, 8.5), 0.82, wet=0.28, tail_sec=0.14)
    s["chime_3.wav"] = master_sfx(fm_bell(79, 0.32, 2.0, 1.3, 7.8), 0.84, wet=0.30, tail_sec=0.16)

    # parry_clash
    n = int(0.38 * SR)
    t = np.arange(n) / SR
    sig = (
        0.48 * sine(1340.0, n) + 0.42 * sine(2120.0, n) + 0.34 * sine(3180.0, n)
        + 0.45 * spectral_filter(white_noise(n, 219), 2600.0, 11000.0) * np.exp(-t * 22.0)
    ) * np.exp(-t * 10.5)
    s["parry_clash.wav"] = master_sfx(sig, 0.88, wet=0.28, tail_sec=0.16)

    # rock_fall
    buf = np.zeros(int(0.64 * SR))
    for i, (dt, fh) in enumerate([(0.0, 145.0), (0.14, 115.0), (0.30, 92.0)]):
        place(buf, dt, punch_hit(fh, 32.0, 0.28, 220 + i), 0.85)
    s["rock_fall.wav"] = master_sfx(buf, 0.88, wet=0.24, tail_sec=0.14)

    # orb_gain
    s["orb_gain.wav"] = master_sfx(arp_bells([79, 84, 91], 0.038, 0.18, 11.0, 1.1), 0.78, wet=0.26, tail_sec=0.12)

    # sfx_spell_miss
    buf = np.zeros(int(0.24 * SR))
    place(buf, 0.0, fm_bell(53, 0.11, 1.5, 1.8, 16.0), 0.75)
    place(buf, 0.08, fm_bell(48, 0.14, 1.5, 1.8, 14.0), 0.78)
    s["sfx_spell_miss.wav"] = master_sfx(buf, 0.76, wet=0.18, tail_sec=0.08)

    # sfx_spell_unleash (Pokémon radiant move launch!)
    buf = np.zeros(int(0.60 * SR))
    nw = int(0.36 * SR)
    tw = np.arange(nw) / SR
    sw = spectral_filter(white_noise(nw, 223), 600.0, 7500.0) * np.sin(math.pi * tw / 0.36) * 0.45
    place(buf, 0.0, sw, 0.85)
    place(buf, 0.01, arp_bells([64, 68, 71, 76, 80, 83, 88], 0.044, 0.28, 7.5, 1.3), 0.85)
    s["sfx_spell_unleash.wav"] = master_sfx(buf, 0.86, wet=0.34, tail_sec=0.20)

    # heal (iconic Pokémon Recover / Healing sparkle!)
    s["heal.wav"] = master_sfx(
        arp_bells([65, 69, 72, 76, 77, 81, 84, 88], 0.056, 0.38, 5.8, 1.1), 0.84, wet=0.36, tail_sec=0.24
    )

    # puma_growl
    n = int(0.58 * SR)
    t = np.arange(n) / SR
    f = (140.0 - 48.0 * t / 0.58) + 38.0 * np.sin(2 * math.pi * 32.0 * t)
    sig = spectral_filter(0.65 * warm_saw(f, n, 12) + 0.45 * white_noise(n, 225), 90.0, 2200.0)
    s["puma_growl.wav"] = master_sfx(sig * env_adsr(n, 0.025, 0.08, 0.75, 0.15), 0.86, wet=0.24, tail_sec=0.14)

    # hurt (Pokémon damage hit)
    buf = np.zeros(int(0.30 * SR))
    place(buf, 0.0, punch_hit(190.0, 50.0, 0.22, 226), 0.85)
    n2 = int(0.24 * SR)
    t2 = np.arange(n2) / SR
    place(buf, 0.0, warm_pulse(390.0 * np.exp(-t2 * 9.0) + 95.0, n2, 0.30, 8) * np.exp(-t2 * 11.0), 0.55)
    s["hurt.wav"] = master_sfx(buf, 0.86, wet=0.18, tail_sec=0.10)

    # === 4. 8 ELEMENTAL STAGE STATE SFX (MODERN POKEMON ELEMENT FEEL) ===

    # sfx_elem_mojado (Water Pulse)
    buf = np.zeros(int(0.52 * SR))
    n1 = int(0.28 * SR)
    t1 = np.arange(n1) / SR
    place(buf, 0.0, spectral_filter(white_noise(n1, 301), 300.0, 3600.0) * np.exp(-t1 * 10.0), 0.68)
    for i, (dt, f0) in enumerate([(0.04, 480.0), (0.13, 640.0), (0.23, 820.0), (0.33, 980.0)]):
        nn = int(0.09 * SR)
        tt = np.arange(nn) / SR
        place(buf, dt, sine(f0 * (1.0 + 0.85 * tt / 0.09), nn) * env_exp(nn, 0.002, 20.0), 0.50)
    s["sfx_elem_mojado.wav"] = master_sfx(buf, 0.84, wet=0.30, tail_sec=0.14)

    # sfx_elem_congelado (Ice Beam crystallize)
    buf = np.zeros(int(0.60 * SR))
    place(buf, 0.0, arp_bells([84, 88, 91, 95, 96, 100], 0.042, 0.32, 6.5, 2.2), 0.84)
    nf = int(0.32 * SR)
    tf = np.arange(nf) / SR
    place(buf, 0.03, spectral_filter(white_noise(nf, 302), 3800.0, 14000.0) * np.exp(-tf * 11.0), 0.48)
    s["sfx_elem_congelado.wav"] = master_sfx(buf, 0.86, wet=0.35, tail_sec=0.20)

    # sfx_elem_caliente (Flamethrower flare)
    n = int(0.56 * SR)
    t = np.arange(n) / SR
    whoosh = spectral_filter(white_noise(n, 303), 160.0, 3100.0) * (np.sin(math.pi * t / 0.56) ** 0.55)
    roar = spectral_filter(warm_saw(110.0 + 160.0 * np.sin(math.pi * t / 0.56), n, 10), 80.0, 1200.0) * 0.45
    buf = 0.78 * whoosh + roar * np.exp(-t * 3.8)
    for dt in [0.09, 0.18, 0.28, 0.38]:
        nn = int(0.045 * SR)
        place(buf, dt, spectral_filter(white_noise(nn, int(dt * 1000)), 3200.0, 11000.0) * env_exp(nn, 0.001, 45.0), 0.45)
    s["sfx_elem_caliente.wav"] = master_sfx(buf, 0.86, wet=0.24, tail_sec=0.14)

    # sfx_elem_enjabonado (Bubble Beam pops)
    buf = np.zeros(int(0.54 * SR))
    for i, (dt, f0) in enumerate([(0.0, 400.0), (0.075, 540.0), (0.15, 700.0), (0.23, 880.0), (0.32, 1120.0)]):
        nn = int(0.08 * SR)
        tt = np.arange(nn) / SR
        place(buf, dt, sine(f0 * (1.0 + 1.05 * (tt / 0.08) ** 1.3), nn) * env_exp(nn, 0.002, 24.0), 0.74)
    s["sfx_elem_enjabonado.wav"] = master_sfx(buf, 0.84, wet=0.28, tail_sec=0.12)

    # sfx_elem_aceitoso (slick cartoon gloop slide)
    n = int(0.44 * SR)
    t = np.arange(n) / SR
    f = 240.0 + 340.0 * np.sin(2 * math.pi * 4.0 * t) * np.exp(-t * 2.4)
    sig = spectral_filter(0.60 * sine(f, n) + 0.45 * warm_pulse(f * 1.5, n, 0.35, 6), 140.0, 2600.0)
    s["sfx_elem_aceitoso.wav"] = master_sfx(sig * env_adsr(n, 0.01, 0.08, 0.72, 0.09), 0.84, wet=0.22, tail_sec=0.10)

    # sfx_elem_oscuro (Night Shade / lights out)
    buf = np.zeros(int(0.60 * SR))
    n1 = int(0.36 * SR)
    t1 = np.arange(n1) / SR
    place(buf, 0.0, warm_saw(620.0 * (2.0 ** (-t1 * 5.8)), n1, 8) * np.exp(-t1 * 4.5), 0.65)
    place(buf, 0.22, fm_bell(57, 0.34, 1.41, 2.4, 5.5), 0.55)
    place(buf, 0.28, fm_bell(75, 0.28, 2.76, 1.8, 6.5), 0.45)
    s["sfx_elem_oscuro.wav"] = master_sfx(buf, 0.84, wet=0.38, tail_sec=0.22)

    # sfx_elem_ruidoso (Hyper Voice / megaphone echo)
    buf = np.zeros(int(0.56 * SR))
    for dt, g, f0 in [(0.0, 0.88, 560.0), (0.14, 0.62, 600.0), (0.28, 0.40, 560.0)]:
        nn = int(0.12 * SR)
        tt = np.arange(nn) / SR
        sig = 0.60 * warm_saw(f0 * (1.0 + 0.06 * np.sin(2 * math.pi * 28 * tt)), nn, 10) + 0.40 * warm_pulse(f0 * 1.02, nn, 0.25, 8)
        place(buf, dt, sig * env_exp(nn, 0.004, 13.0), g)
    s["sfx_elem_ruidoso.wav"] = master_sfx(buf, 0.85, wet=0.28, tail_sec=0.14)

    # sfx_elem_pegajoso (sticky gloop stretch)
    n = int(0.46 * SR)
    t = np.arange(n) / SR
    f = 180.0 + 230.0 * (t / 0.46) ** 1.5 + 58.0 * np.sin(2 * math.pi * 20.0 * t)
    sig = spectral_filter(0.65 * warm_pulse(f, n, 0.40, 8) + 0.40 * white_noise(n, 308), 110.0, 1800.0)
    s["sfx_elem_pegajoso.wav"] = master_sfx(sig * env_adsr(n, 0.015, 0.06, 0.72, 0.08), 0.84, wet=0.20, tail_sec=0.10)

    # === 5. 6 POKEMON-STYLE SUPER-COMBO SPECTACLES ===

    # sfx_combo_electro (Thunderbolt!)
    buf = np.zeros(int(0.84 * SR))
    place(buf, 0.0, punch_hit(260, 42, 0.34, 401), 0.85)
    nz = int(0.56 * SR)
    tz = np.arange(nz) / SR
    zap_f = 920.0 + 680.0 * np.sign(np.sin(2 * math.pi * 42.0 * tz))
    zap = (0.48 * warm_pulse(zap_f, nz, 0.15, 8) + 0.60 * spectral_filter(white_noise(nz, 402), 1800.0, 12500.0))
    place(buf, 0.01, zap * np.exp(-tz * 4.8), 0.80)
    place(buf, 0.04, arp_bells([76, 80, 83, 88, 92, 95, 100], 0.052, 0.34, 6.0, 2.0), 0.72)
    s["sfx_combo_electro.wav"] = master_sfx(buf, 0.92, wet=0.34, tail_sec=0.22)

    # sfx_combo_deep_freeze (Sheer Cold / Blizzard!)
    buf = np.zeros(int(0.88 * SR))
    place(buf, 0.0, punch_hit(180, 36, 0.30, 403), 0.72)
    place(buf, 0.02, arp_bells([84, 88, 91, 96, 100, 103, 108], 0.048, 0.44, 4.8, 2.4), 0.90)
    nsh = int(0.42 * SR)
    tsh = np.arange(nsh) / SR
    place(buf, 0.06, spectral_filter(white_noise(nsh, 404), 3400.0, 14000.0) * np.exp(-tsh * 7.5), 0.58)
    s["sfx_combo_deep_freeze.wav"] = master_sfx(buf, 0.90, wet=0.40, tail_sec=0.28)

    # sfx_combo_steam_sauna (Scald / Steam Eruption!)
    buf = np.zeros(int(0.86 * SR))
    nst = int(0.76 * SR)
    tst = np.arange(nst) / SR
    place(buf, 0.03, spectral_filter(white_noise(nst, 405), 1100.0, 7200.0) * (np.sin(math.pi * tst / 0.76) ** 0.5), 0.72)
    nwh = int(0.48 * SR)
    twh = np.arange(nwh) / SR
    wh = sine(1220.0 + 480.0 * twh / 0.48 + 24.0 * np.sin(2 * math.pi * 14 * twh), nwh)
    place(buf, 0.0, wh * env_adsr(nwh, 0.04, 0.06, 0.78, 0.14), 0.55)
    s["sfx_combo_steam_sauna.wav"] = master_sfx(buf, 0.88, wet=0.32, tail_sec=0.20)

    # sfx_combo_slip_slide (cartoon slide-whistle + dizzy stars)
    buf = np.zeros(int(0.82 * SR))
    nsl = int(0.46 * SR)
    tsl = np.arange(nsl) / SR
    fsl = 360.0 + 1380.0 * np.sin(math.pi * (tsl / 0.46) ** 0.85)
    place(buf, 0.0, (0.72 * sine(fsl, nsl) + 0.28 * warm_pulse(fsl, nsl, 0.45, 6)) * env_adsr(nsl, 0.01, 0.05, 0.85, 0.06), 0.76)
    place(buf, 0.34, arp_bells([81, 86, 81, 88, 81, 93], 0.050, 0.20, 9.0, 1.3), 0.75)
    s["sfx_combo_slip_slide.wav"] = master_sfx(buf, 0.88, wet=0.28, tail_sec=0.16)

    # sfx_combo_fire_boom (Fire Blast explosion!)
    buf = np.zeros(int(0.92 * SR))
    nex = int(0.84 * SR)
    tex = np.arange(nex) / SR
    boom = sine(165.0 * np.exp(-tex * 7.5) + 30.0, nex) * np.exp(-tex * 3.8)
    blast = spectral_filter(white_noise(nex, 406), 80.0, 2800.0) * np.exp(-tex * 4.2)
    place(buf, 0.0, 0.75 * boom + 0.88 * blast, 0.94)
    place(buf, 0.05, brass_stab([60, 67, 72, 79], 0.38), 0.52)
    s["sfx_combo_fire_boom.wav"] = master_sfx(buf, 0.92, wet=0.34, tail_sec=0.24)

    # sfx_combo_chaos (Metronome / Carnival Chaos!)
    buf = np.zeros(int(0.86 * SR))
    place(buf, 0.0, arp_bells([72, 78, 75, 83, 79, 87, 84, 91, 96], 0.048, 0.28, 7.0, 1.8), 0.76)
    place(buf, 0.14, punch_hit(240, 70, 0.18, 407), 0.60)
    place(buf, 0.36, brass_stab([72, 76, 79, 84], 0.34), 0.65)
    s["sfx_combo_chaos.wav"] = master_sfx(buf, 0.90, wet=0.34, tail_sec=0.22)

    # === 6. 8 ENEMY COUNTERATTACK FX ===

    # sfx_counter_tears
    buf = np.zeros(int(0.40 * SR))
    for i, dt in enumerate([0.0, 0.075, 0.15, 0.23]):
        nn = int(0.085 * SR)
        tt = np.arange(nn) / SR
        place(buf, dt, sine((880 - i * 85) * (1.0 - 0.35 * tt / 0.085), nn) * env_exp(nn, 0.002, 20.0), 0.75)
    s["sfx_counter_tears.wav"] = master_sfx(buf, 0.82, wet=0.26, tail_sec=0.12)

    # sfx_counter_flash
    n = int(0.32 * SR)
    t = np.arange(n) / SR
    sig = warm_pulse(1500.0 * np.exp(-t * 7.0) + 460.0, n, 0.18, 8) * np.exp(-t * 11.0) * 0.65
    sig += spectral_filter(white_noise(n, 502), 2800.0, 12000.0) * np.exp(-t * 15.0) * 0.60
    s["sfx_counter_flash.wav"] = master_sfx(sig, 0.84, wet=0.26, tail_sec=0.12)

    # sfx_counter_splash
    n = int(0.38 * SR)
    t = np.arange(n) / SR
    sig = spectral_filter(white_noise(n, 503), 260.0, 3200.0) * np.exp(-t * 8.5)
    sig += sine(350.0 + 380.0 * np.exp(-t * 13.0), n) * np.exp(-t * 14.0) * 0.42
    s["sfx_counter_splash.wav"] = master_sfx(sig, 0.84, wet=0.26, tail_sec=0.12)

    # sfx_counter_wind
    n = int(0.44 * SR)
    t = np.arange(n) / SR
    arch = np.sin(math.pi * t / 0.44) ** 0.8
    sig = spectral_filter(white_noise(n, 504), 240.0, 2600.0) * arch
    sig += sine(290.0 + 250.0 * np.sin(math.pi * t / 0.44), n) * arch * 0.24
    s["sfx_counter_wind.wav"] = master_sfx(sig, 0.84, wet=0.28, tail_sec=0.14)

    # sfx_counter_mud
    n = int(0.38 * SR)
    t = np.arange(n) / SR
    f = 210.0 * np.exp(-t * 10.5) + 62.0 + 34.0 * np.sin(2 * math.pi * 34 * t)
    sig = 0.60 * sine(f, n) + 0.55 * spectral_filter(white_noise(n, 505), 110.0, 1400.0)
    s["sfx_counter_mud.wav"] = master_sfx(sig * np.exp(-t * 9.0), 0.84, wet=0.20, tail_sec=0.10)

    # sfx_counter_stink
    n = int(0.46 * SR)
    t = np.arange(n) / SR
    f = 275.0 - 105.0 * t / 0.46 + 34.0 * np.sin(2 * math.pi * 9.0 * t)
    sig = spectral_filter(0.60 * warm_saw(f, n, 10) + 0.40 * warm_pulse(f * 0.99, n, 0.35, 6), 120.0, 2200.0)
    s["sfx_counter_stink.wav"] = master_sfx(sig * env_adsr(n, 0.02, 0.06, 0.72, 0.10), 0.82, wet=0.24, tail_sec=0.12)

    # sfx_counter_music
    buf = np.zeros(int(0.42 * SR))
    place(buf, 0.0, brass_stab([67, 73, 78], 0.17), 0.72)
    place(buf, 0.17, brass_stab([66, 72, 77], 0.22), 0.72)
    s["sfx_counter_music.wav"] = master_sfx(buf, 0.84, wet=0.26, tail_sec=0.12)

    # sfx_counter_sparkles
    s["sfx_counter_sparkles.wav"] = master_sfx(
        arp_bells([86, 83, 89, 81, 86], 0.044, 0.22, 9.0, 1.4), 0.82, wet=0.30, tail_sec=0.14
    )

    # === 7. COMBAT POLISH, UI & EXPLORATION SFX ===

    # sfx_prompt_reject
    buf = np.zeros(int(0.36 * SR))
    place(buf, 0.0, brass_stab([58, 61], 0.13), 0.72)
    place(buf, 0.14, brass_stab([54, 57], 0.18), 0.74)
    s["sfx_prompt_reject.wav"] = master_sfx(buf, 0.78, wet=0.20, tail_sec=0.10)

    # sfx_enemy_ko (classic Pokémon fainting spiral + victory pop!)
    buf = np.zeros(int(0.76 * SR))
    n1 = int(0.46 * SR)
    t1 = np.arange(n1) / SR
    f1 = 840.0 * (2.0 ** (-t1 * 3.6)) * (1.0 + 0.06 * np.sin(2 * math.pi * 16.0 * t1))
    place(buf, 0.0, (0.60 * warm_saw(f1, n1, 8) + 0.40 * sine(f1, n1)) * np.exp(-t1 * 2.8), 0.70)
    place(buf, 0.38, punch_hit(185, 36, 0.28, 601), 0.85)
    place(buf, 0.40, arp_bells([72, 76, 79, 84], 0.046, 0.26, 7.0), 0.75)
    s["sfx_enemy_ko.wav"] = master_sfx(buf, 0.88, wet=0.30, tail_sec=0.18)

    # sfx_ui_click (crisp Nintendo/Pokémon menu blip)
    s["sfx_ui_click.wav"] = master_sfx(fm_bell(81, 0.085, 2.0, 0.9, 24.0), 0.72, wet=0.14, tail_sec=0.05)

    # sfx_prompt_open
    s["sfx_prompt_open.wav"] = master_sfx(arp_bells([76, 83], 0.045, 0.14, 15.0, 0.9), 0.74, wet=0.20, tail_sec=0.08)

    # sfx_prompt_submit
    s["sfx_prompt_submit.wav"] = master_sfx(arp_bells([72, 79, 84], 0.042, 0.22, 10.0, 1.2), 0.82, wet=0.26, tail_sec=0.12)

    # sfx_truck_jump
    n = int(0.26 * SR)
    t = np.arange(n) / SR
    f = 220.0 * (2.0 ** (t * 5.8))
    sig = 0.55 * warm_pulse(f, n, 0.30, 8) + 0.45 * sine(f, n)
    s["sfx_truck_jump.wav"] = master_sfx(sig * env_exp(n, 0.003, 8.5), 0.78, wet=0.20, tail_sec=0.08)

    # sfx_truck_land
    n = int(0.22 * SR)
    t = np.arange(n) / SR
    thud = sine(140.0 * np.exp(-t * 22.0) + 46.0, n) * np.exp(-t * 16.0)
    sand = spectral_filter(white_noise(n, 607), 300.0, 2600.0) * np.exp(-t * 20.0) * 0.55
    s["sfx_truck_land.wav"] = master_sfx(thud + sand, 0.78, wet=0.16, tail_sec=0.06)

    # sfx_step_sand, sfx_step_wood, sfx_step_grass (gentle, organic, never tiring)
    n = int(0.075 * SR)
    t = np.arange(n) / SR
    s["sfx_step_sand.wav"] = master_sfx(
        spectral_filter(white_noise(n, 608), 350.0, 3200.0) * np.exp(-t * 48.0) * 0.75
        + sine(120.0, n) * np.exp(-t * 60.0) * 0.25,
        0.58, wet=0.10, tail_sec=0.03,
    )
    s["sfx_step_wood.wav"] = master_sfx(
        (0.62 * sine(260.0, n) + 0.38 * sine(540.0, n)) * np.exp(-t * 54.0),
        0.60, wet=0.14, tail_sec=0.04,
    )
    s["sfx_step_grass.wav"] = master_sfx(
        spectral_filter(white_noise(n, 610), 750.0, 4800.0) * np.exp(-t * 45.0) * 0.80
        + sine(150.0, n) * np.exp(-t * 62.0) * 0.20,
        0.56, wet=0.10, tail_sec=0.03,
    )

    # sfx_camera_pan
    n = int(0.26 * SR)
    t = np.arange(n) / SR
    arch = np.sin(math.pi * t / 0.26)
    sig = spectral_filter(white_noise(n, 611), 220.0, 1800.0) * arch * 0.52 + sine(420 + 160 * t / 0.26, n) * arch * 0.22
    s["sfx_camera_pan.wav"] = master_sfx(sig, 0.62, wet=0.22, tail_sec=0.08)

    return s


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--overwrite-jingles", action="store_true", help="Also overwrite the 4 Lyria musical jingles")
    args = parser.parse_args()

    catalog = build_sfx_catalog()
    written = 0
    skipped = 0
    for filename, stereo in sorted(catalog.items()):
        out_path = OUT_DIR / filename
        if filename in LYRIA_JINGLES and out_path.is_file() and not args.overwrite_jingles:
            skipped += 1
            continue
        write_wav(out_path, stereo)
        written += 1
    print(f"Generated {written} HD-2D Pokémon-style SFX (44.1 kHz stereo); preserved {skipped} Lyria jingles.")


if __name__ == "__main__":
    main()
