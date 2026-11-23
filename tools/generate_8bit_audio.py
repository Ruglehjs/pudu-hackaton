"""GBA / Game Boy (Mario & Luigi: Superstar Saga style) 8-bit Music & SFX Generator
for Pudú Fantasy.

Synthesizes 10 distinct chiptune music tracks (4 biome overworld themes, 4 campaign
battle themes, victory fanfare, defeat jingle) with sample-exact seamless loops for
beat_sync.lua, plus 61 cohesive 8-bit/GBA sound effects (26 base SFX + 8 elemental
states + 6 super-combos + 8 enemy counterattacks + combat/UI/exploration polish).

Usage:
    python tools/generate_8bit_audio.py
"""

from __future__ import annotations

import math
import re
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets" / "audio"
SR = 22050  # Authentic GBA-era mixer sample rate: bright, crisp, lightweight.


# ---------------------------------------------------------------------------
# Pitch & Timing Helpers
# ---------------------------------------------------------------------------

NOTE_SEMITONES = {
    "C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3,
    "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8,
    "A": 9, "A#": 10, "Bb": 10, "B": 11,
}
NOTE_RE = re.compile(r"^([A-G][#b]?)(-?\d)$")


def note_to_midi(name: str | int | float | None) -> float | None:
    if name is None or name == "R" or name == "-":
        return None
    if isinstance(name, (int, float)):
        return float(name)
    m = NOTE_RE.match(name.strip())
    if not m:
        raise ValueError(f"Invalid note: {name!r}")
    return float((int(m.group(2)) + 1) * 12 + NOTE_SEMITONES[m.group(1)])


def midi_to_hz(midi: float) -> float:
    return 440.0 * (2.0 ** ((midi - 69.0) / 12.0))


def write_wav(path: Path, samples: np.ndarray, sr: int = SR) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    clipped = np.clip(samples, -1.0, 1.0)
    pcm = (clipped * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes(pcm.tobytes())


# ---------------------------------------------------------------------------
# Band-Limited Chiptune Oscillators & LFSR Noise
# ---------------------------------------------------------------------------

def _phase_from_freq(freq: np.ndarray | float, n: int) -> np.ndarray:
    if np.isscalar(freq):
        return np.arange(n, dtype=np.float64) * (float(freq) / SR)
    return np.cumsum(np.asarray(freq, dtype=np.float64) / SR)


def osc_pulse(freq: np.ndarray | float, n: int, duty: float = 0.25, max_harm: int = 16) -> np.ndarray:
    """Band-limited pulse wave (no harsh aliasing, authentic crisp GB/GBA bite)."""
    f_max = float(np.max(freq)) if not np.isscalar(freq) else float(freq)
    if f_max <= 1.0:
        return np.zeros(n, dtype=np.float64)
    nyq_limit = max(1, int((SR * 0.44) / max(f_max, 20.0)))
    k_max = min(max_harm, nyq_limit)
    phase = _phase_from_freq(freq, n) * (2.0 * math.pi)
    out = np.zeros(n, dtype=np.float64)
    for k in range(1, k_max + 1):
        amp = (2.0 / (k * math.pi)) * math.sin(math.pi * k * duty)
        if abs(amp) > 1e-4:
            out += amp * np.cos(k * phase)
    return out


def osc_saw(freq: np.ndarray | float, n: int, max_harm: int = 16) -> np.ndarray:
    f_max = float(np.max(freq)) if not np.isscalar(freq) else float(freq)
    if f_max <= 1.0:
        return np.zeros(n, dtype=np.float64)
    nyq_limit = max(1, int((SR * 0.44) / max(f_max, 20.0)))
    k_max = min(max_harm, nyq_limit)
    phase = _phase_from_freq(freq, n) * (2.0 * math.pi)
    out = np.zeros(n, dtype=np.float64)
    for k in range(1, k_max + 1):
        out += ((-1.0) ** (k + 1) / k) * np.sin(k * phase)
    return out * (2.0 / math.pi)


def osc_triangle(freq: np.ndarray | float, n: int, max_harm: int = 9) -> np.ndarray:
    f_max = float(np.max(freq)) if not np.isscalar(freq) else float(freq)
    if f_max <= 1.0:
        return np.zeros(n, dtype=np.float64)
    nyq_limit = max(1, int((SR * 0.44) / max(f_max, 20.0)))
    phase = _phase_from_freq(freq, n) * (2.0 * math.pi)
    out = np.zeros(n, dtype=np.float64)
    for idx in range(max_harm):
        k = 2 * idx + 1
        if k > nyq_limit:
            break
        out += (((-1.0) ** idx) / (k * k)) * np.sin(k * phase)
    return out * (8.0 / (math.pi * math.pi))


def osc_sine(freq: np.ndarray | float, n: int) -> np.ndarray:
    return np.sin(_phase_from_freq(freq, n) * (2.0 * math.pi))


def lfsr_noise(n: int, clock_hz: float = 8000.0, short_mode: bool = False, seed: int = 0x5A3D) -> np.ndarray:
    """Authentic retro LFSR stepped noise (7-bit metallic or 15-bit crisp)."""
    step = max(1.0, SR / max(100.0, clock_hz))
    num_steps = int(math.ceil(n / step)) + 2
    reg = seed & 0x7FFF
    if reg == 0:
        reg = 1
    vals = np.empty(num_steps, dtype=np.float64)
    for i in range(num_steps):
        vals[i] = 1.0 if (reg & 1) else -1.0
        bit = (reg ^ (reg >> 1)) & 1
        reg >>= 1
        if short_mode:
            reg = (reg & ~(1 << 6)) | (bit << 6)
        else:
            reg |= bit << 14
    idx = np.minimum((np.arange(n) / step).astype(np.int64), num_steps - 1)
    return vals[idx]


def one_pole_lowpass(x: np.ndarray, cutoff_hz: float) -> np.ndarray:
    if cutoff_hz >= SR * 0.45:
        return x
    rc = 1.0 / (2.0 * math.pi * max(20.0, cutoff_hz))
    dt = 1.0 / SR
    alpha = dt / (rc + dt)
    out = np.empty_like(x)
    y = 0.0
    for i in range(len(x)):
        y += alpha * (x[i] - y)
        out[i] = y
    return out


def one_pole_highpass(x: np.ndarray, cutoff_hz: float) -> np.ndarray:
    return x - one_pole_lowpass(x, cutoff_hz)


def adsr_env(n: int, attack: float = 0.006, decay: float = 0.08, sustain: float = 0.65, release: float = 0.03) -> np.ndarray:
    env = np.full(n, sustain, dtype=np.float64)
    a = min(n, max(1, int(attack * SR)))
    d = min(n - a, max(0, int(decay * SR)))
    r = min(n, max(1, int(release * SR)))
    env[:a] = np.linspace(0.0, 1.0, a, endpoint=False)
    if d > 0:
        env[a:a + d] = np.linspace(1.0, sustain, d, endpoint=False)
    if r > 0:
        env[n - r:] *= np.linspace(1.0, 0.0, r)
    return env


def exp_env(n: int, attack: float = 0.003, decay_rate: float = 8.0) -> np.ndarray:
    t = np.arange(n, dtype=np.float64) / SR
    a = min(n, max(1, int(attack * SR)))
    env = np.exp(-t * decay_rate)
    env[:a] *= np.linspace(0.0, 1.0, a, endpoint=False)
    fade = min(n, max(1, int(0.012 * SR)))
    env[n - fade:] *= np.linspace(1.0, 0.0, fade)
    return env


# ---------------------------------------------------------------------------
# Expressive GBA / Superstar Saga Instruments
# ---------------------------------------------------------------------------

def synth_note(inst: str, midi: float, dur_sec: float, vel: float = 1.0, slide_from: float | None = None) -> np.ndarray:
    n = max(16, int(round(dur_sec * SR)))
    t = np.arange(n, dtype=np.float64) / SR
    f0 = midi_to_hz(midi)

    if inst == "lead_bright":
        vib_env = np.clip((t - 0.10) / 0.14, 0.0, 1.0)
        freq = f0 * (2.0 ** (0.14 * vib_env * np.sin(2.0 * math.pi * 5.8 * t) / 12.0))
        if slide_from is not None:
            s_len = min(n, int(0.045 * SR))
            freq[:s_len] *= np.linspace(midi_to_hz(slide_from) / f0, 1.0, s_len)
        sig = 0.72 * osc_pulse(freq, n, duty=0.25, max_harm=14) + 0.28 * osc_pulse(freq * 1.002, n, duty=0.50, max_harm=10)
        env = adsr_env(n, attack=0.005, decay=0.08, sustain=0.68, release=min(0.035, dur_sec * 0.25))
        return sig * env * vel

    if inst == "brass_gba":
        # Punchy Mario & Luigi: Superstar Saga brass/accordion lead!
        scoop = np.ones(n, dtype=np.float64)
        sc_n = min(n, int(0.028 * SR))
        scoop[:sc_n] = np.linspace(0.985, 1.0, sc_n)
        vib = 2.0 ** (0.12 * np.clip((t - 0.12) / 0.12, 0.0, 1.0) * np.sin(2.0 * math.pi * 5.6 * t) / 12.0)
        freq = f0 * scoop * vib
        if slide_from is not None:
            s_len = min(n, int(0.05 * SR))
            freq[:s_len] *= np.linspace(midi_to_hz(slide_from) / f0, 1.0, s_len)
        sig = 0.58 * osc_saw(freq, n, max_harm=14) + 0.42 * osc_pulse(freq * 0.9985, n, duty=0.25, max_harm=12)
        env = adsr_env(n, attack=0.008, decay=0.07, sustain=0.74, release=min(0.035, dur_sec * 0.22))
        return sig * env * vel

    if inst == "lead_flute":
        # Airy chiptune quena / ocarina / forest flute
        vib = 2.0 ** (0.16 * np.clip((t - 0.11) / 0.15, 0.0, 1.0) * np.sin(2.0 * math.pi * 5.2 * t) / 12.0)
        freq = f0 * vib
        if slide_from is not None:
            s_len = min(n, int(0.055 * SR))
            freq[:s_len] *= np.linspace(midi_to_hz(slide_from) / f0, 1.0, s_len)
        sig = 0.60 * osc_pulse(freq, n, duty=0.50, max_harm=7) + 0.40 * osc_triangle(freq, n, max_harm=5)
        breath = lfsr_noise(n, clock_hz=5200.0, seed=int(midi * 37) + 7) * np.exp(-t * 28.0) * 0.08
        env = adsr_env(n, attack=0.015, decay=0.09, sustain=0.72, release=min(0.045, dur_sec * 0.30))
        return (sig + breath) * env * vel

    if inst == "marimba":
        # Bouncy GBA wooden mallet / Andean charango pluck
        sig = (
            0.70 * osc_triangle(f0, n, max_harm=5)
            + 0.28 * osc_pulse(f0 * 2.0, n, duty=0.25, max_harm=6) * np.exp(-t * 18.0)
            + 0.18 * osc_sine(f0 * 4.0, n) * np.exp(-t * 36.0)
        )
        env = exp_env(n, attack=0.002, decay_rate=max(6.5, 2.6 / max(dur_sec, 0.08)))
        return sig * env * vel

    if inst == "bell_sparkle":
        sig = (
            0.62 * osc_sine(f0, n)
            + 0.25 * osc_sine(f0 * 2.0, n) * np.exp(-t * 7.0)
            + 0.16 * osc_sine(f0 * 3.0, n) * np.exp(-t * 14.0)
            + 0.12 * osc_pulse(f0 * 2.0, n, duty=0.125, max_harm=5) * np.exp(-t * 16.0)
        )
        env = exp_env(n, attack=0.002, decay_rate=max(4.5, 2.1 / max(dur_sec, 0.1)))
        return sig * env * vel

    if inst == "organ_ghost":
        # Spooky baroque pipe-organ pulse+saw for El Caleuche
        vib = 2.0 ** (0.18 * np.sin(2.0 * math.pi * 6.0 * t) / 12.0)
        freq = f0 * vib
        sig = (
            0.52 * osc_pulse(freq, n, duty=0.125, max_harm=14)
            + 0.30 * osc_pulse(freq * 2.0, n, duty=0.50, max_harm=8)
            + 0.24 * osc_saw(freq * 0.5, n, max_harm=10)
        )
        env = adsr_env(n, attack=0.010, decay=0.06, sustain=0.80, release=min(0.04, dur_sec * 0.25))
        return sig * env * vel

    if inst == "bass_bouncy":
        # Punchy GBA slap-triangle bass
        sig = (
            0.78 * osc_triangle(f0, n, max_harm=7)
            + 0.26 * osc_pulse(f0, n, duty=0.25, max_harm=6) * np.exp(-t * 11.0)
            + 0.15 * osc_pulse(f0 * 2.0, n, duty=0.50, max_harm=4) * np.exp(-t * 28.0)
        )
        env = adsr_env(n, attack=0.003, decay=0.06, sustain=0.72, release=min(0.025, dur_sec * 0.25))
        return sig * env * vel

    if inst == "chord_pad":
        sig = 0.65 * osc_pulse(f0, n, duty=0.125, max_harm=10) + 0.35 * osc_triangle(f0, n, max_harm=5)
        env = exp_env(n, attack=0.003, decay_rate=9.0)
        return sig * env * vel

    raise ValueError(f"Unknown instrument: {inst}")


def synth_drum(kind: str, vel: float = 1.0, seed: int = 1) -> np.ndarray:
    if kind == "K":
        n = int(0.14 * SR)
        t = np.arange(n, dtype=np.float64) / SR
        freq = 44.0 + 130.0 * np.exp(-t * 36.0)
        body = osc_triangle(freq, n, max_harm=4) * np.exp(-t * 18.0)
        click = lfsr_noise(n, clock_hz=9000.0, seed=11 + seed) * np.exp(-t * 95.0) * 0.22
        return (body + click) * vel

    if kind == "S":
        n = int(0.14 * SR)
        t = np.arange(n, dtype=np.float64) / SR
        noise = one_pole_highpass(lfsr_noise(n, clock_hz=11500.0, seed=31 + seed), 750.0) * np.exp(-t * 24.0)
        body = osc_triangle(115.0 + 95.0 * np.exp(-t * 42.0), n, max_harm=4) * np.exp(-t * 28.0)
        return (0.68 * noise + 0.45 * body) * vel

    if kind == "H":
        n = int(0.042 * SR)
        t = np.arange(n, dtype=np.float64) / SR
        noise = one_pole_highpass(lfsr_noise(n, clock_hz=16000.0, short_mode=False, seed=71 + seed), 3600.0)
        return noise * np.exp(-t * 72.0) * 0.42 * vel

    if kind == "O":
        n = int(0.13 * SR)
        t = np.arange(n, dtype=np.float64) / SR
        noise = one_pole_highpass(lfsr_noise(n, clock_hz=15500.0, short_mode=False, seed=97 + seed), 3200.0)
        return noise * np.exp(-t * 22.0) * 0.40 * vel

    if kind == "C":  # Woodblock / clave / castanet snap
        n = int(0.065 * SR)
        t = np.arange(n, dtype=np.float64) / SR
        sig = (0.72 * osc_sine(960.0, n) + 0.35 * osc_sine(1480.0, n)) * np.exp(-t * 58.0)
        return sig * 0.65 * vel

    if kind in ("T1", "T2", "T3"):
        base_f = {"T1": 210.0, "T2": 155.0, "T3": 110.0}[kind]
        n = int(0.15 * SR)
        t = np.arange(n, dtype=np.float64) / SR
        freq = base_f * (0.55 + 0.65 * np.exp(-t * 24.0))
        sig = osc_triangle(freq, n, max_harm=5) * np.exp(-t * 16.0)
        return sig * 0.85 * vel

    return np.zeros(16, dtype=np.float64)


# ---------------------------------------------------------------------------
# Sample-Exact Cyclic Track Builder
# ---------------------------------------------------------------------------

class TrackBuilder:
    def __init__(self, bpm: float, beats: int, loop: bool = True, swing: float = 0.0):
        self.bpm = float(bpm)
        self.beats = int(beats)
        self.loop = loop
        self.swing = float(swing)  # 0.0 = straight, 0.14 = bouncy jazz swing on 8ths
        self.sec_per_beat = 60.0 / self.bpm
        self.total_samples = int(round(self.beats * self.sec_per_beat * SR))
        self.buf = np.zeros(self.total_samples, dtype=np.float64)

    def _beat_to_sample(self, beat: float) -> int:
        # Apply swing to offbeat 8th notes (fractional beat near 0.5)
        if self.swing > 0.0:
            whole = math.floor(beat)
            frac = beat - whole
            if 0.45 <= frac <= 0.55:
                beat = whole + 0.5 + self.swing
        return int(round(beat * self.sec_per_beat * SR))

    def mix(self, start_beat: float, seg: np.ndarray, gain: float = 1.0) -> None:
        if len(seg) == 0:
            return
        start = self._beat_to_sample(start_beat)
        if self.loop:
            idx = (start + np.arange(len(seg))) % self.total_samples
            np.add.at(self.buf, idx, seg * gain)
        else:
            if start >= self.total_samples:
                return
            end = min(self.total_samples, start + len(seg))
            self.buf[start:end] += seg[:end - start] * gain

    def add_melody(
        self,
        events: list[tuple[str | None, float]],
        inst: str,
        gain: float = 0.30,
        start_beat: float = 0.0,
        gate: float = 0.86,
        octave_shift: int = 0,
    ) -> float:
        cur = start_beat
        prev_midi = None
        for ev in events:
            note, dur = ev[0], ev[1]
            slide = ev[2] if len(ev) > 2 else False
            midi = note_to_midi(note)
            if midi is not None:
                m = midi + octave_shift * 12
                seg = synth_note(inst, m, dur * self.sec_per_beat * gate, vel=1.0, slide_from=(prev_midi if slide else None))
                self.mix(cur, seg, gain)
                prev_midi = m
            else:
                prev_midi = None
            cur += dur
        return cur

    def add_arps(
        self,
        chords: list[tuple[list[str], float]],
        inst: str = "marimba",
        step: float = 0.5,
        gain: float = 0.16,
        pattern: tuple[int, ...] = (0, 1, 2, 1),
        start_beat: float = 0.0,
        gate: float = 0.72,
    ) -> None:
        cur = start_beat
        for notes, dur in chords:
            midis = [note_to_midi(x) for x in notes if note_to_midi(x) is not None]
            steps = int(round(dur / step))
            for i in range(steps):
                if midis:
                    m = midis[pattern[i % len(pattern)] % len(midis)]
                    seg = synth_note(inst, m, step * self.sec_per_beat * gate)
                    self.mix(cur + i * step, seg, gain)
            cur += dur

    def add_drum_pattern(self, pattern: dict[str, str], bars: int, start_beat: float = 0.0, gain: float = 0.28) -> None:
        """Each pattern string is 16 chars per 4-beat bar (16th notes)."""
        for bar in range(bars):
            base = start_beat + bar * 4.0
            for drum_kind, grid in pattern.items():
                clean = grid.replace(" ", "")
                step_dur = 4.0 / len(clean)
                for idx, ch in enumerate(clean):
                    if ch in ("x", "X", "o"):
                        vel = 1.0 if ch == "X" else (0.72 if ch == "x" else 0.48)
                        self.mix(base + idx * step_dur, synth_drum(drum_kind, vel=vel, seed=bar * 17 + idx), gain)

    def render(self, target_rms: float = 0.185) -> np.ndarray:
        sig = self.buf.copy()
        rms = float(np.sqrt(np.mean(sig * sig))) + 1e-9
        sig = sig * (target_rms / rms)
        # Warm GBA-style soft limiter
        sig = np.tanh(sig * 1.15) / math.tanh(1.15)
        peak = float(np.max(np.abs(sig))) + 1e-9
        if peak > 0.88:
            sig *= 0.88 / peak
        if not self.loop:
            fade = min(len(sig), int(0.04 * SR))
            sig[-fade:] *= np.linspace(1.0, 0.0, fade)
        return sig


# ---------------------------------------------------------------------------
# 10 Distinct 8-bit / GBA Music Compositions
# ---------------------------------------------------------------------------

def compose_overworld_desierto() -> np.ndarray:
    """Atacama (116 BPM, 64 beats): Sunny Andean D Dorian quena + charango groove."""
    tb = TrackBuilder(bpm=116.0, beats=64, loop=True)

    # Section A (32 beats): sunny Andean pentatonic/Dorian melody
    mel_a = [
        ("D5", 0.5), ("F5", 0.5), ("A5", 1.0), ("G5", 0.5), ("F5", 0.5), ("D5", 1.0),
        ("C5", 0.5), ("D5", 0.5), ("F5", 1.0), ("E5", 0.5), ("D5", 0.5), ("C5", 1.0),
        ("D5", 0.5), ("F5", 0.5), ("A5", 0.5), ("C6", 0.5), ("A5", 1.0), ("G5", 1.0),
        ("F5", 0.5), ("G5", 0.5), ("A5", 1.5), ("R", 0.5), ("G5", 0.5), ("F5", 0.5),
        ("D5", 0.5), ("F5", 0.5), ("A5", 1.0), ("C6", 0.5), ("A5", 0.5), ("G5", 1.0),
        ("F5", 0.5), ("E5", 0.5), ("D5", 1.0), ("C5", 1.0), ("E5", 1.0),
        ("G5", 0.5), ("A5", 0.5), ("C6", 1.0), ("A5", 0.5), ("G5", 0.5), ("F5", 0.5), ("E5", 0.5),
        ("D5", 2.5), ("R", 1.5),
    ]
    # Section B (32 beats): bright sunlit Atacama mirador lift (F Major -> Bb -> A7)
    mel_b = [
        ("A5", 1.0), ("C6", 0.5), ("D6", 0.5), ("C6", 1.0), ("A5", 1.0),
        ("G5", 0.5), ("A5", 0.5), ("Bb5", 1.0), ("A5", 0.5), ("G5", 0.5), ("F5", 1.0),
        ("G5", 0.5), ("A5", 0.5), ("C6", 1.0), ("A5", 0.5), ("G5", 0.5), ("F5", 1.0),
        ("E5", 1.0), ("G5", 1.0), ("A5", 1.5), ("R", 0.5),
        ("D6", 0.5), ("C6", 0.5), ("A5", 1.0), ("G5", 0.5), ("F5", 0.5), ("D5", 1.0),
        ("F5", 0.5), ("G5", 0.5), ("A5", 1.0), ("C6", 1.0), ("G5", 1.0),
        ("F5", 0.5), ("E5", 0.5), ("D5", 0.5), ("F5", 0.5), ("E5", 0.5), ("C5", 0.5), ("E5", 1.0),
        ("D5", 2.5), ("R", 1.5),
    ]
    tb.add_melody(mel_a, "lead_flute", gain=0.31, start_beat=0.0, gate=0.84)
    tb.add_melody(mel_b, "lead_bright", gain=0.27, start_beat=32.0, gate=0.82)

    chords = [
        (["D4", "F4", "A4"], 4), (["C4", "E4", "G4"], 4),
        (["D4", "F4", "A4"], 4), (["G4", "B4", "D5"], 4),
        (["D4", "F4", "A4"], 4), (["C4", "E4", "G4"], 4),
        (["Bb3", "D4", "F4"], 2), (["A3", "C#4", "E4"], 2), (["D4", "F4", "A4"], 4),
        # B
        (["F4", "A4", "C5"], 4), (["Bb3", "D4", "F4"], 4),
        (["C4", "E4", "G4"], 4), (["A3", "C#4", "E4"], 4),
        (["D4", "F4", "A4"], 4), (["G4", "B4", "D5"], 4),
        (["Bb3", "D4", "F4"], 2), (["A3", "C#4", "E4"], 2), (["D4", "F4", "A4"], 4),
    ]
    tb.add_arps(chords, inst="marimba", step=0.5, gain=0.19, pattern=(0, 2, 1, 2, 0, 1, 2, 1), gate=0.68)

    bass = []
    roots = [
        ("D2", "A2"), ("C2", "G2"), ("D2", "A2"), ("G2", "D3"),
        ("D2", "A2"), ("C2", "G2"), ("Bb2", "A2"), ("D2", "A2"),
        ("F2", "C3"), ("Bb2", "F2"), ("C2", "G2"), ("A2", "E2"),
        ("D2", "A2"), ("G2", "D3"), ("Bb2", "A2"), ("D2", "A2"),
    ]
    for r1, r2 in roots:
        bass.extend([(r1, 1.0), (r2, 0.5), (r1, 0.5), (r2, 1.0), (r1, 0.5), (r2, 0.5)])
    tb.add_melody(bass, "bass_bouncy", gain=0.34, start_beat=0.0, gate=0.72)

    tb.add_drum_pattern({
        "K": "X... ..x. X... ....",
        "C": "..x. x... ..x. .x.x",
        "H": "x.x. x.x. x.x. x.o.",
        "S": ".... x... .... x...",
    }, bars=16, gain=0.22)
    return tb.render()


def compose_overworld_costa() -> np.ndarray:
    """Valparaíso (124 BPM, 64 beats): Jaunty harbor brass/accordion bounce in G Major."""
    tb = TrackBuilder(bpm=124.0, beats=64, loop=True)

    mel_a = [
        ("G5", 0.5), ("B5", 0.5), ("D6", 1.0), ("B5", 0.5), ("C6", 0.5), ("A5", 1.0),
        ("G5", 0.5), ("A5", 0.5), ("B5", 1.0), ("D5", 1.5), ("R", 0.5),
        ("E5", 0.5), ("G5", 0.5), ("C6", 1.0), ("B5", 0.5), ("A5", 0.5), ("G5", 1.0),
        ("A5", 1.0), ("F#5", 0.5), ("G5", 0.5), ("A5", 1.5), ("R", 0.5),
        ("G5", 0.5), ("B5", 0.5), ("D6", 1.0), ("E6", 0.5), ("D6", 0.5), ("B5", 1.0),
        ("C6", 0.5), ("B5", 0.5), ("A5", 1.0), ("G5", 1.0), ("E5", 1.0),
        ("D5", 0.5), ("G5", 0.5), ("B5", 0.5), ("D6", 0.5), ("C6", 0.5), ("A5", 0.5), ("F#5", 1.0),
        ("G5", 2.5), ("R", 1.5),
    ]
    mel_b = [
        ("E5", 1.0), ("G5", 0.5), ("B5", 0.5), ("E6", 1.0), ("D6", 1.0),
        ("C6", 0.5), ("B5", 0.5), ("A5", 1.0), ("G5", 1.5), ("R", 0.5),
        ("C6", 1.0), ("B5", 0.5), ("A5", 0.5), ("G5", 1.0), ("E5", 1.0),
        ("F#5", 0.5), ("G5", 0.5), ("A5", 1.0), ("D6", 1.5), ("R", 0.5),
        ("B5", 0.5), ("D6", 0.5), ("G6", 1.0), ("E6", 0.5), ("D6", 0.5), ("B5", 1.0),
        ("C6", 0.5), ("A5", 0.5), ("E5", 1.0), ("G5", 1.0), ("C6", 1.0),
        ("B5", 0.5), ("G5", 0.5), ("A5", 0.5), ("F#5", 0.5), ("D5", 0.5), ("F#5", 0.5), ("A5", 1.0),
        ("G5", 2.5), ("R", 1.5),
    ]
    tb.add_melody(mel_a, "brass_gba", gain=0.25, start_beat=0.0, gate=0.80)
    tb.add_melody(mel_b, "lead_bright", gain=0.26, start_beat=32.0, gate=0.82)

    chords = [
        (["G4", "B4", "D5"], 4), (["G4", "B4", "D5"], 4),
        (["C4", "E4", "G4"], 4), (["D4", "F#4", "A4"], 4),
        (["G4", "B4", "D5"], 4), (["C4", "E4", "G4"], 4),
        (["G4", "B4", "D5"], 2), (["D4", "F#4", "A4"], 2), (["G4", "B4", "D5"], 4),
        # B
        (["E4", "G4", "B4"], 4), (["A4", "C5", "E5"], 4),
        (["C4", "E4", "G4"], 4), (["D4", "F#4", "A4"], 4),
        (["G4", "B4", "D5"], 4), (["C4", "E4", "G4"], 4),
        (["D4", "F#4", "A4"], 4), (["G4", "B4", "D5"], 4),
    ]
    tb.add_arps(chords, inst="marimba", step=0.5, gain=0.17, pattern=(0, 1, 2, 1), gate=0.60)

    bass = []
    pairs = [
        ("G2", "D2"), ("G2", "B2"), ("C2", "G2"), ("D2", "A2"),
        ("G2", "D2"), ("C2", "G2"), ("D2", "A2"), ("G2", "D2"),
        ("E2", "B2"), ("A2", "E2"), ("C2", "G2"), ("D2", "A2"),
        ("G2", "D2"), ("C2", "G2"), ("D2", "A2"), ("G2", "D2"),
    ]
    for a, b in pairs:
        bass.extend([(a, 1.0), (b, 1.0), (a, 0.5), (b, 0.5), (a, 1.0)])
    tb.add_melody(bass, "bass_bouncy", gain=0.35, start_beat=0.0, gate=0.68)

    tb.add_drum_pattern({
        "K": "X... .... X.x. ....",
        "S": ".... X... .... X..o",
        "H": "x.x. x.o. x.x. x.x.",
        "C": ".... ..x. .... .x..",
    }, bars=16, gain=0.23)
    return tb.render()


def compose_overworld_bosque() -> np.ndarray:
    """Bosque Valdiviano (112 BPM, 64 beats): Lush whimsical F Major / Lydian enchanted woods."""
    tb = TrackBuilder(bpm=112.0, beats=64, loop=True)

    mel_a = [
        ("F5", 0.5), ("A5", 0.5), ("C6", 1.0), ("B5", 0.5), ("C6", 0.5), ("A5", 1.0),
        ("G5", 0.5), ("A5", 0.5), ("F5", 1.5), ("R", 0.5), ("C5", 1.0),
        ("D5", 0.5), ("F5", 0.5), ("A5", 1.0), ("G5", 0.5), ("F5", 0.5), ("E5", 1.0),
        ("G5", 1.0), ("A5", 0.5), ("G5", 0.5), ("C5", 1.5), ("R", 0.5),
        ("F5", 0.5), ("A5", 0.5), ("C6", 1.0), ("D6", 0.5), ("C6", 0.5), ("A5", 1.0),
        ("Bb5", 0.5), ("A5", 0.5), ("G5", 1.0), ("F5", 1.0), ("D5", 1.0),
        ("E5", 0.5), ("G5", 0.5), ("C6", 1.0), ("A5", 0.5), ("G5", 0.5), ("E5", 1.0),
        ("F5", 2.5), ("R", 1.5),
    ]
    mel_b = [
        ("D5", 1.0), ("F5", 0.5), ("A5", 0.5), ("D6", 1.0), ("C6", 1.0),
        ("Bb5", 0.5), ("A5", 0.5), ("G5", 1.0), ("A5", 1.5), ("R", 0.5),
        ("G5", 0.5), ("Bb5", 0.5), ("D6", 1.0), ("C6", 0.5), ("Bb5", 0.5), ("A5", 1.0),
        ("G5", 1.0), ("E5", 1.0), ("C6", 1.5), ("R", 0.5),
        ("A5", 0.5), ("C6", 0.5), ("F6", 1.0), ("E6", 0.5), ("D6", 0.5), ("C6", 1.0),
        ("Bb5", 0.5), ("A5", 0.5), ("G5", 1.0), ("F5", 1.0), ("D5", 1.0),
        ("G5", 0.5), ("A5", 0.5), ("Bb5", 0.5), ("G5", 0.5), ("A5", 0.5), ("G5", 0.5), ("E5", 1.0),
        ("F5", 2.5), ("R", 1.5),
    ]
    tb.add_melody(mel_a, "lead_flute", gain=0.31, start_beat=0.0, gate=0.88)
    tb.add_melody(mel_b, "lead_flute", gain=0.31, start_beat=32.0, gate=0.88)

    chords = [
        (["F4", "A4", "C5", "E5"], 4), (["G4", "B4", "D5"], 4),
        (["D4", "F4", "A4"], 4), (["C4", "E4", "G4"], 4),
        (["F4", "A4", "C5"], 4), (["Bb3", "D4", "F4"], 4),
        (["C4", "E4", "G4"], 4), (["F4", "A4", "C5"], 4),
        # B
        (["D4", "F4", "A4"], 4), (["Bb3", "D4", "F4"], 4),
        (["G4", "Bb4", "D5"], 4), (["C4", "E4", "G4"], 4),
        (["F4", "A4", "C5"], 4), (["Bb3", "D4", "F4"], 4),
        (["G4", "Bb4", "D5"], 2), (["C4", "E4", "G4"], 2), (["F4", "A4", "C5"], 4),
    ]
    tb.add_arps(chords, inst="bell_sparkle", step=0.5, gain=0.16, pattern=(0, 1, 2, 3, 2, 1, 0, 2), gate=0.85)

    bass = []
    roots = [
        ("F2", "C3"), ("G2", "D3"), ("D2", "A2"), ("C2", "G2"),
        ("F2", "C3"), ("Bb2", "F2"), ("C2", "G2"), ("F2", "C3"),
        ("D2", "A2"), ("Bb2", "F2"), ("G2", "D3"), ("C2", "G2"),
        ("F2", "C3"), ("Bb2", "F2"), ("G2", "C2"), ("F2", "C3"),
    ]
    for a, b in roots:
        bass.extend([(a, 1.5), (b, 0.5), (a, 1.0), (b, 1.0)])
    tb.add_melody(bass, "bass_bouncy", gain=0.33, start_beat=0.0, gate=0.76)

    tb.add_drum_pattern({
        "K": "X... ..x. .... x...",
        "C": ".... x... ..x. ....",
        "H": "x.o. x.o. x.o. x.o.",
    }, bars=16, gain=0.19)
    return tb.render()


def compose_overworld_chiloe() -> np.ndarray:
    """Chiloé (108 BPM, 64 beats): Misty E Dorian/Minor maritime folklore with crystalline bells."""
    tb = TrackBuilder(bpm=108.0, beats=64, loop=True)

    mel_a = [
        ("E5", 1.0), ("G5", 0.5), ("B5", 0.5), ("C#6", 1.0), ("B5", 1.0),
        ("A5", 0.5), ("G5", 0.5), ("F#5", 1.0), ("E5", 1.5), ("R", 0.5),
        ("G5", 0.5), ("A5", 0.5), ("B5", 1.0), ("D6", 0.5), ("C#6", 0.5), ("B5", 1.0),
        ("A5", 1.0), ("F#5", 1.0), ("B5", 1.5), ("R", 0.5),
        ("E5", 0.5), ("G5", 0.5), ("B5", 1.0), ("E6", 0.5), ("D6", 0.5), ("B5", 1.0),
        ("C6", 0.5), ("B5", 0.5), ("A5", 1.0), ("G5", 1.0), ("F#5", 1.0),
        ("G5", 0.5), ("F#5", 0.5), ("E5", 0.5), ("D#5", 0.5), ("E5", 0.5), ("F#5", 0.5), ("B4", 1.0),
        ("E5", 2.5), ("R", 1.5),
    ]
    mel_b = [
        ("G5", 1.0), ("B5", 0.5), ("D6", 0.5), ("C6", 1.0), ("B5", 1.0),
        ("A5", 0.5), ("B5", 0.5), ("C6", 1.0), ("A5", 1.5), ("R", 0.5),
        ("F#5", 0.5), ("A5", 0.5), ("B5", 1.0), ("D#6", 0.5), ("B5", 0.5), ("F#5", 1.0),
        ("G5", 1.0), ("A5", 1.0), ("B5", 1.5), ("R", 0.5),
        ("E6", 0.5), ("D6", 0.5), ("B5", 1.0), ("C6", 0.5), ("B5", 0.5), ("A5", 1.0),
        ("G5", 0.5), ("A5", 0.5), ("B5", 1.0), ("F#5", 1.0), ("D#5", 1.0),
        ("E5", 0.5), ("G5", 0.5), ("A5", 0.5), ("B5", 0.5), ("A5", 0.5), ("G5", 0.5), ("F#5", 1.0),
        ("E5", 2.5), ("R", 1.5),
    ]
    tb.add_melody(mel_a, "lead_flute", gain=0.30, start_beat=0.0, gate=0.88)
    tb.add_melody(mel_b, "organ_ghost", gain=0.23, start_beat=32.0, gate=0.84)

    chords = [
        (["E4", "G4", "B4"], 4), (["D4", "F#4", "A4"], 4),
        (["C4", "E4", "G4"], 4), (["B3", "D#4", "F#4"], 4),
        (["E4", "G4", "B4"], 4), (["A3", "C4", "E4"], 4),
        (["C4", "E4", "G4"], 2), (["B3", "D#4", "F#4"], 2), (["E4", "G4", "B4"], 4),
        # B
        (["G4", "B4", "D5"], 4), (["A4", "C5", "E5"], 4),
        (["B3", "D#4", "F#4"], 4), (["E4", "G4", "B4"], 4),
        (["C4", "E4", "G4"], 4), (["A3", "C4", "E4"], 4),
        (["B3", "D#4", "F#4"], 4), (["E4", "G4", "B4"], 4),
    ]
    tb.add_arps(chords, inst="bell_sparkle", step=0.5, gain=0.17, pattern=(0, 2, 1, 2), gate=0.90)

    bass = []
    roots = [
        ("E2", "B2"), ("D2", "A2"), ("C2", "G2"), ("B1", "F#2"),
        ("E2", "B2"), ("A2", "E2"), ("C2", "B1"), ("E2", "B2"),
        ("G2", "D3"), ("A2", "E2"), ("B1", "F#2"), ("E2", "B2"),
        ("C2", "G2"), ("A2", "E2"), ("B1", "F#2"), ("E2", "B2"),
    ]
    for a, b in roots:
        bass.extend([(a, 1.5), (b, 0.5), (a, 1.0), (b, 1.0)])
    tb.add_melody(bass, "bass_bouncy", gain=0.33, start_beat=0.0, gate=0.80)

    tb.add_drum_pattern({
        "K": "X... .... X..x ....",
        "T2": ".... .... .... .x..",
        "S": ".... x... .... x...",
        "O": "x... x... x... x...",
    }, bars=16, gain=0.20)
    return tb.render()


def compose_battle_pila_ropa() -> np.ndarray:
    """Pila de Ropa (138 BPM, 64 beats): Hyper-bouncy Superstar Saga comedy spin-cycle battle!"""
    tb = TrackBuilder(bpm=138.0, beats=64, loop=True)

    mel_a = [
        ("C5", 0.5), ("E5", 0.5), ("G5", 0.5), ("A5", 0.5), ("Bb5", 0.5), ("A5", 0.5), ("G5", 0.5), ("E5", 0.5),
        ("F5", 0.5), ("A5", 0.5), ("C6", 0.5), ("A5", 0.5), ("G5", 1.0), ("E5", 1.0),
        ("D5", 0.5), ("F5", 0.5), ("A5", 0.5), ("G5", 0.5), ("F5", 0.5), ("E5", 0.5), ("D5", 0.5), ("F5", 0.5),
        ("E5", 0.5), ("G5", 0.5), ("C6", 1.0), ("G5", 1.0), ("R", 1.0),
        ("C5", 0.5), ("E5", 0.5), ("G5", 0.5), ("C6", 0.5), ("D6", 0.5), ("C6", 0.5), ("Bb5", 0.5), ("A5", 0.5),
        ("G5", 0.5), ("A5", 0.5), ("G5", 0.5), ("F5", 0.5), ("E5", 1.0), ("C5", 1.0),
        ("D5", 0.5), ("E5", 0.5), ("F5", 0.5), ("G5", 0.5), ("A5", 0.5), ("B5", 0.5), ("D6", 1.0),
        ("C6", 1.5), ("G5", 0.5), ("C6", 1.0), ("R", 1.0),
    ]
    mel_b = [
        ("F5", 0.5), ("A5", 0.5), ("C6", 1.0), ("D6", 0.5), ("C6", 0.5), ("A5", 1.0),
        ("G5", 0.5), ("B5", 0.5), ("D6", 1.0), ("E6", 0.5), ("D6", 0.5), ("B5", 1.0),
        ("E5", 0.5), ("G5", 0.5), ("B5", 1.0), ("A5", 0.5), ("C6", 0.5), ("E6", 1.0),
        ("D6", 0.5), ("C6", 0.5), ("B5", 0.5), ("A5", 0.5), ("G5", 1.5), ("R", 0.5),
        ("F5", 0.5), ("G5", 0.5), ("A5", 0.5), ("C6", 0.5), ("B5", 0.5), ("A5", 0.5), ("G5", 1.0),
        ("E5", 0.5), ("G5", 0.5), ("C6", 0.5), ("G5", 0.5), ("A5", 1.0), ("E5", 1.0),
        ("D5", 0.5), ("F5", 0.5), ("A5", 0.5), ("C6", 0.5), ("B5", 0.5), ("G5", 0.5), ("D6", 1.0),
        ("C6", 1.0), ("G5", 0.5), ("E5", 0.5), ("C5", 1.0), ("R", 1.0),
    ]
    tb.add_melody(mel_a, "lead_bright", gain=0.28, start_beat=0.0, gate=0.78)
    tb.add_melody(mel_b, "brass_gba", gain=0.25, start_beat=32.0, gate=0.80)

    # Spinning washing-machine marimba arpeggios!
    chords = [
        (["C4", "E4", "G4", "Bb4"], 4), (["F4", "A4", "C5"], 4),
        (["D4", "F4", "A4"], 4), (["C4", "E4", "G4"], 4),
        (["C4", "E4", "G4", "Bb4"], 4), (["F4", "A4", "C5"], 4),
        (["D4", "F4", "A4"], 2), (["G4", "B4", "D5"], 2), (["C4", "E4", "G4"], 4),
        # B
        (["F4", "A4", "C5"], 4), (["G4", "B4", "D5"], 4),
        (["E4", "G4", "B4"], 2), (["A4", "C5", "E5"], 2), (["D4", "F4", "A4"], 2), (["G4", "B4", "D5"], 2),
        (["F4", "A4", "C5"], 4), (["C4", "E4", "G4"], 2), (["A3", "C4", "E4"], 2),
        (["D4", "F4", "A4"], 2), (["G4", "B4", "D5"], 2), (["C4", "E4", "G4"], 4),
    ]
    tb.add_arps(chords, inst="marimba", step=0.25, gain=0.16, pattern=(0, 1, 2, 3, 2, 1, 0, 2), gate=0.62)

    bass_roots = [
        "C2", "F2", "D2", "C2", "C2", "F2", "G2", "C2",
        "F2", "G2", "E2", "D2", "F2", "C2", "G2", "C2",
    ]
    bass = []
    for root in bass_roots:
        m = int(note_to_midi(root))
        bass.extend([
            (m, 0.5), (m + 12, 0.5), (m + 7, 0.5), (m + 12, 0.5),
            (m, 0.5), (m + 7, 0.5), (m + 10, 0.5), (m + 12, 0.5),
        ])
    tb.add_melody(bass, "bass_bouncy", gain=0.33, start_beat=0.0, gate=0.68)

    tb.add_drum_pattern({
        "K": "X... ..x. X.x. ....",
        "S": ".... X... .... X..x",
        "H": "x.x. x.x. x.x. x.o.",
        "C": "..x. .... ..x. .x..",
    }, bars=16, gain=0.25)
    return tb.render()


def compose_battle_gaviota() -> np.ndarray:
    """Gaviota Mafiosa (132 BPM, 64 beats): Cheeky swung harbor-mafia jazz-chiptune in A Minor!"""
    tb = TrackBuilder(bpm=132.0, beats=64, loop=True, swing=0.14)

    mel_a = [
        ("A5", 0.5), ("C6", 0.5), ("D6", 0.5), ("Eb6", 0.5), ("D6", 0.5), ("C6", 0.5), ("A5", 1.0),
        ("G5", 0.5), ("A5", 0.5), ("C6", 1.0), ("E5", 1.5), ("R", 0.5),
        ("D5", 0.5), ("F5", 0.5), ("A5", 0.5), ("C6", 0.5), ("B5", 0.5), ("G#5", 0.5), ("E5", 1.0),
        ("A5", 0.5), ("G5", 0.5), ("E5", 0.5), ("G5", 0.5), ("A5", 1.5), ("R", 0.5),
        ("A5", 0.5), ("C6", 0.5), ("E6", 1.0), ("Eb6", 0.5), ("D6", 0.5), ("C6", 1.0),
        ("B5", 0.5), ("D6", 0.5), ("F6", 0.5), ("E6", 0.5), ("D6", 1.0), ("B5", 1.0),
        ("C6", 0.5), ("A5", 0.5), ("G#5", 0.5), ("B5", 0.5), ("E6", 1.0), ("G#5", 1.0),
        ("A5", 2.0), ("E5", 0.5), ("G5", 0.5), ("A5", 1.0),
    ]
    mel_b = [
        ("F5", 1.0), ("A5", 0.5), ("C6", 0.5), ("Eb6", 1.0), ("D6", 0.5), ("C6", 0.5),
        ("E5", 1.0), ("G#5", 0.5), ("B5", 0.5), ("D6", 1.0), ("C6", 0.5), ("B5", 0.5),
        ("A5", 0.5), ("C6", 0.5), ("E6", 1.0), ("G6", 0.5), ("E6", 0.5), ("C6", 1.0),
        ("D6", 0.5), ("C6", 0.5), ("B5", 0.5), ("A5", 0.5), ("G#5", 1.5), ("R", 0.5),
        ("F5", 0.5), ("A5", 0.5), ("C6", 0.5), ("D6", 0.5), ("Eb6", 0.5), ("D6", 0.5), ("C6", 1.0),
        ("E5", 0.5), ("G#5", 0.5), ("B5", 0.5), ("E6", 0.5), ("D6", 1.0), ("B5", 1.0),
        ("C6", 0.5), ("B5", 0.5), ("A5", 0.5), ("G5", 0.5), ("F5", 0.5), ("E5", 0.5), ("G#5", 1.0),
        ("A5", 1.5), ("C6", 0.5), ("A5", 1.0), ("R", 1.0),
    ]
    tb.add_melody(mel_a, "brass_gba", gain=0.27, start_beat=0.0, gate=0.76)
    tb.add_melody(mel_b, "lead_bright", gain=0.27, start_beat=32.0, gate=0.78)

    chords = [
        (["A4", "C5", "E5", "G5"], 4), (["A4", "C5", "E5"], 4),
        (["D4", "F4", "A4", "C5"], 2), (["E4", "G#4", "B4", "D5"], 2), (["A4", "C5", "E5"], 4),
        (["A4", "C5", "E5"], 4), (["D4", "F4", "A4"], 4),
        (["E4", "G#4", "B4", "D5"], 4), (["A4", "C5", "E5"], 4),
        # B
        (["F4", "A4", "C5", "Eb5"], 4), (["E4", "G#4", "B4", "D5"], 4),
        (["A4", "C5", "E5"], 4), (["B3", "D#4", "F#4"], 2), (["E4", "G#4", "B4"], 2),
        (["F4", "A4", "C5", "Eb5"], 4), (["E4", "G#4", "B4", "D5"], 4),
        (["D4", "F4", "A4"], 2), (["E4", "G#4", "B4"], 2), (["A4", "C5", "E5"], 4),
    ]
    tb.add_arps(chords, inst="chord_pad", step=1.0, gain=0.14, pattern=(0, 2, 1, 3), gate=0.38)

    # Walking jazz bassline!
    walk = [
        ("A2", 1), ("C3", 1), ("E3", 1), ("Eb3", 1),
        ("D3", 1), ("C3", 1), ("B2", 1), ("G#2", 1),
        ("D2", 1), ("F2", 1), ("E2", 1), ("G#2", 1),
        ("A2", 1), ("E2", 1), ("G2", 1), ("G#2", 1),
        ("A2", 1), ("C3", 1), ("E3", 1), ("G3", 1),
        ("F3", 1), ("E3", 1), ("D3", 1), ("B2", 1),
        ("E2", 1), ("G#2", 1), ("B2", 1), ("D3", 1),
        ("A2", 1), ("E2", 1), ("A2", 1), ("G2", 1),
        # B
        ("F2", 1), ("A2", 1), ("C3", 1), ("Eb3", 1),
        ("E2", 1), ("G#2", 1), ("B2", 1), ("D3", 1),
        ("A2", 1), ("C3", 1), ("E3", 1), ("C3", 1),
        ("B2", 1), ("D#3", 1), ("E3", 1), ("G#2", 1),
        ("F2", 1), ("A2", 1), ("C3", 1), ("D3", 1),
        ("E2", 1), ("G#2", 1), ("B2", 1), ("D3", 1),
        ("D2", 1), ("F2", 1), ("E2", 1), ("G#2", 1),
        ("A2", 1), ("E2", 1), ("A2", 1), ("R", 1),
    ]
    tb.add_melody(walk, "bass_bouncy", gain=0.35, start_beat=0.0, gate=0.82)

    tb.add_drum_pattern({
        "K": "X... .... X... ..x.",
        "S": ".... X... .... X...",
        "H": "x... x.x. x... x.x.",
        "O": ".... ..o. .... ..o.",
        "C": "..x. .... .... .x..",
    }, bars=16, gain=0.23)
    return tb.render()


def compose_battle_puma() -> np.ndarray:
    """Puma Dramático (142 BPM, 64 beats): Grandiose theatrical diva tango-opera in D Minor!"""
    tb = TrackBuilder(bpm=142.0, beats=64, loop=True)

    mel_a = [
        ("D5", 0.5), ("F5", 0.5), ("A5", 1.0), ("Bb5", 0.5), ("A5", 0.5), ("G#5", 0.5), ("A5", 0.5),
        ("F5", 1.0), ("D5", 1.0), ("A4", 1.5), ("R", 0.5),
        ("G5", 0.5), ("Bb5", 0.5), ("D6", 1.0), ("C6", 0.5), ("Bb5", 0.5), ("A5", 1.0),
        ("G#5", 0.5), ("A5", 0.5), ("B5", 0.5), ("C#6", 0.5), ("A5", 1.5), ("R", 0.5),
        ("D6", 1.0), ("C#6", 0.5), ("D6", 0.5), ("F6", 1.0), ("D6", 1.0),
        ("C6", 0.5), ("Bb5", 0.5), ("A5", 1.0), ("G5", 1.0), ("F5", 1.0),
        ("E5", 0.5), ("G5", 0.5), ("Bb5", 0.5), ("A5", 0.5), ("G5", 0.5), ("F5", 0.5), ("E5", 0.5), ("C#5", 0.5),
        ("D5", 2.0), ("A5", 0.5), ("F5", 0.5), ("D5", 1.0),
    ]
    mel_b = [
        ("G5", 1.0), ("Bb5", 0.5), ("D6", 0.5), ("C6", 1.0), ("Bb5", 1.0),
        ("A5", 0.5), ("G5", 0.5), ("F5", 1.0), ("E5", 1.0), ("C5", 1.0),
        ("F5", 0.5), ("A5", 0.5), ("C6", 1.0), ("Bb5", 0.5), ("A5", 0.5), ("G5", 1.0),
        ("A5", 1.0), ("C#6", 1.0), ("E6", 1.5), ("R", 0.5),
        ("F6", 0.5), ("E6", 0.5), ("D6", 1.0), ("C6", 0.5), ("Bb5", 0.5), ("A5", 1.0),
        ("Bb5", 0.5), ("A5", 0.5), ("G5", 1.0), ("F5", 1.0), ("E5", 1.0),
        ("D5", 0.5), ("F5", 0.5), ("A5", 0.5), ("D6", 0.5), ("C#6", 0.5), ("A5", 0.5), ("E6", 1.0),
        ("D6", 1.5), ("A5", 0.5), ("D6", 1.0), ("R", 1.0),
    ]
    tb.add_melody(mel_a, "brass_gba", gain=0.28, start_beat=0.0, gate=0.80)
    tb.add_melody(mel_b, "lead_bright", gain=0.27, start_beat=32.0, gate=0.82)

    chords = [
        (["D4", "F4", "A4"], 4), (["D4", "F4", "A4"], 4),
        (["G4", "Bb4", "D5"], 4), (["A4", "C#5", "E5"], 4),
        (["D4", "F4", "A4"], 4), (["G4", "Bb4", "D5"], 4),
        (["E4", "G4", "Bb4"], 2), (["A4", "C#5", "E5"], 2), (["D4", "F4", "A4"], 4),
        # B
        (["G4", "Bb4", "D5"], 4), (["C4", "E4", "G4", "Bb4"], 4),
        (["F4", "A4", "C5"], 4), (["A4", "C#5", "E5"], 4),
        (["D4", "F4", "A4"], 4), (["G4", "Bb4", "D5"], 4),
        (["D4", "F4", "A4"], 2), (["A4", "C#5", "E5"], 2), (["D4", "F4", "A4"], 4),
    ]
    tb.add_arps(chords, inst="marimba", step=0.25, gain=0.15, pattern=(0, 1, 2, 1, 2, 1, 0, 2), gate=0.58)

    # Dramatic tango habanera bass!
    roots = [
        ("D2", "A2"), ("D2", "A2"), ("G2", "D3"), ("A2", "E2"),
        ("D2", "A2"), ("G2", "D3"), ("E2", "A2"), ("D2", "A2"),
        ("G2", "D3"), ("C2", "G2"), ("F2", "C3"), ("A2", "E2"),
        ("D2", "A2"), ("G2", "D3"), ("D2", "A2"), ("D2", "A2"),
    ]
    bass = []
    for a, b in roots:
        bass.extend([(a, 1.5), (b, 0.5), (a, 1.0), (b, 1.0)])
    tb.add_melody(bass, "bass_bouncy", gain=0.35, start_beat=0.0, gate=0.70)

    tb.add_drum_pattern({
        "K": "X... ..x. X... x...",
        "S": ".... X..x .... X...",
        "C": "x..x ..x. x..x ..x.",
        "H": "x.x. x.x. x.x. x.o.",
    }, bars=16, gain=0.25)
    return tb.render()


def compose_battle_caleuche() -> np.ndarray:
    """El Caleuche (148 BPM, 64 beats): Epic Ghost-Ship Final Boss 8-bit in C# Minor!"""
    tb = TrackBuilder(bpm=148.0, beats=64, loop=True)

    mel_a = [
        ("C#5", 0.5), ("E5", 0.5), ("G#5", 0.5), ("B5", 0.5), ("C#6", 1.0), ("B5", 0.5), ("G#5", 0.5),
        ("A5", 0.5), ("G#5", 0.5), ("F#5", 1.0), ("E5", 1.0), ("D#5", 1.0),
        ("C#5", 0.5), ("E5", 0.5), ("G#5", 0.5), ("C#6", 0.5), ("D#6", 1.0), ("C#6", 0.5), ("B5", 0.5),
        ("G#5", 1.5), ("F#5", 0.5), ("G#5", 1.5), ("R", 0.5),
        ("E6", 0.5), ("D#6", 0.5), ("C#6", 1.0), ("B5", 0.5), ("C#6", 0.5), ("A5", 1.0),
        ("B5", 0.5), ("A5", 0.5), ("G#5", 1.0), ("F#5", 1.0), ("E5", 1.0),
        ("D#5", 0.5), ("F#5", 0.5), ("A5", 0.5), ("G#5", 0.5), ("F#5", 0.5), ("D#5", 0.5), ("G#5", 1.0),
        ("C#6", 1.5), ("G#5", 0.5), ("C#6", 1.0), ("R", 1.0),
    ]
    mel_b = [
        ("F#5", 0.5), ("A5", 0.5), ("C#6", 1.0), ("D#6", 0.5), ("C#6", 0.5), ("A5", 1.0),
        ("G#5", 0.5), ("C#6", 0.5), ("E6", 1.0), ("D#6", 0.5), ("C#6", 0.5), ("G#5", 1.0),
        ("A5", 0.5), ("B5", 0.5), ("C#6", 0.5), ("D#6", 0.5), ("E6", 1.0), ("D#6", 1.0),
        ("G#5", 0.5), ("C6", 0.5), ("D#6", 1.0), ("G#6", 1.5), ("R", 0.5),
        ("E6", 0.5), ("D#6", 0.5), ("C#6", 0.5), ("B5", 0.5), ("A5", 0.5), ("G#5", 0.5), ("F#5", 1.0),
        ("G#5", 0.5), ("A5", 0.5), ("B5", 0.5), ("C#6", 0.5), ("D#6", 1.0), ("B5", 1.0),
        ("C#6", 0.5), ("G#5", 0.5), ("A5", 0.5), ("F#5", 0.5), ("G#5", 0.5), ("D#5", 0.5), ("G#5", 1.0),
        ("C#6", 2.0), ("G#5", 0.5), ("C#6", 0.5), ("R", 1.0),
    ]
    tb.add_melody(mel_a, "organ_ghost", gain=0.25, start_beat=0.0, gate=0.84)
    tb.add_melody(mel_a, "lead_bright", gain=0.14, start_beat=0.0, gate=0.72)
    tb.add_melody(mel_b, "lead_bright", gain=0.27, start_beat=32.0, gate=0.82)
    tb.add_melody(mel_b, "brass_gba", gain=0.15, start_beat=32.0, gate=0.76)

    # Relentless storm 16th-note chiptune arpeggios!
    chords = [
        (["C#4", "E4", "G#4"], 4), (["A3", "C#4", "E4"], 4),
        (["B3", "D#4", "F#4"], 4), (["G#3", "C4", "D#4"], 4),
        (["C#4", "E4", "G#4"], 4), (["A3", "C#4", "E4"], 2), (["B3", "D#4", "F#4"], 2),
        (["D#4", "F#4", "A4"], 2), (["G#3", "C4", "D#4"], 2), (["C#4", "E4", "G#4"], 4),
        # B
        (["F#4", "A4", "C#5"], 4), (["C#4", "E4", "G#4"], 4),
        (["A3", "C#4", "E4"], 2), (["B3", "D#4", "F#4"], 2), (["G#3", "C4", "D#4"], 4),
        (["E4", "G#4", "B4"], 2), (["F#4", "A4", "C#5"], 2), (["B3", "D#4", "F#4"], 4),
        (["A3", "C#4", "E4"], 2), (["G#3", "C4", "D#4"], 2), (["C#4", "E4", "G#4"], 4),
    ]
    tb.add_arps(chords, inst="chord_pad", step=0.25, gain=0.15, pattern=(0, 1, 2, 1), gate=0.65)

    # Driving octave-gallop final-boss bass!
    boss_roots = [
        "C#2", "A1", "B1", "G#1", "C#2", "A1", "G#1", "C#2",
        "F#1", "C#2", "A1", "G#1", "E2", "B1", "G#1", "C#2",
    ]
    bass = []
    for root in boss_roots:
        m = int(note_to_midi(root))
        for _ in range(4):
            bass.extend([(m, 0.5), (m + 12, 0.5)])
    tb.add_melody(bass, "bass_bouncy", gain=0.34, start_beat=0.0, gate=0.72)

    tb.add_drum_pattern({
        "K": "X.x. ..x. X.x. ..x.",
        "S": ".... X... .... X..x",
        "H": "x.x. x.x. x.x. x.x.",
        "T1": ".... .... .... ..x.",
        "T2": ".... .... .... ...x",
    }, bars=16, gain=0.26)
    return tb.render()


def compose_victory() -> np.ndarray:
    """Victory Fanfare (138 BPM, 32 beats, non-looping): Superstar Saga jubilant win!"""
    tb = TrackBuilder(bpm=138.0, beats=32, loop=False)

    mel = [
        # Classic triumphant 4-beat fanfare pickup
        ("C5", 0.33), ("C5", 0.33), ("C5", 0.34), ("G5", 1.0), ("E5", 0.5), ("G5", 0.5), ("C6", 1.0),
        # Joyful hopping victory melody
        ("A5", 0.5), ("B5", 0.5), ("C6", 1.0), ("G5", 0.5), ("E5", 0.5), ("C5", 1.0),
        ("D5", 0.5), ("F5", 0.5), ("A5", 1.0), ("G5", 1.0), ("E5", 1.0),
        ("F5", 0.5), ("A5", 0.5), ("C6", 1.0), ("B5", 0.5), ("A5", 0.5), ("G5", 1.0),
        ("E5", 0.5), ("G5", 0.5), ("C6", 1.0), ("D6", 1.0), ("E6", 1.0),
        ("F6", 0.5), ("E6", 0.5), ("D6", 0.5), ("C6", 0.5), ("B5", 0.5), ("C6", 0.5), ("D6", 1.0),
        ("E6", 0.5), ("D6", 0.5), ("C6", 0.5), ("G5", 0.5), ("A5", 0.5), ("B5", 0.5), ("D6", 1.0),
        ("C6", 3.5), ("R", 0.5),
    ]
    tb.add_melody(mel, "brass_gba", gain=0.27, start_beat=0.0, gate=0.84)
    tb.add_melody(mel, "bell_sparkle", gain=0.16, start_beat=0.0, gate=0.90)

    chords = [
        (["C4", "E4", "G4"], 4), (["C4", "E4", "G4"], 4),
        (["F4", "A4", "C5"], 2), (["G4", "B4", "D5"], 2), (["F4", "A4", "C5"], 2), (["G4", "B4", "D5"], 2),
        (["C4", "E4", "G4"], 4), (["F4", "A4", "C5"], 2), (["G4", "B4", "D5"], 2),
        (["G4", "B4", "D5"], 4), (["C4", "E4", "G4", "C5"], 4),
    ]
    tb.add_arps(chords, inst="marimba", step=0.5, gain=0.16, pattern=(0, 1, 2, 1), gate=0.72)

    bass = [
        ("C2", 1), ("G2", 1), ("C2", 1), ("G2", 1),
        ("C2", 1), ("E2", 1), ("G2", 1), ("C3", 1),
        ("F2", 1), ("A2", 1), ("G2", 1), ("B2", 1),
        ("F2", 1), ("A2", 1), ("G2", 1), ("D2", 1),
        ("C2", 1), ("G2", 1), ("A2", 1), ("E2", 1),
        ("F2", 1), ("C3", 1), ("G2", 1), ("D3", 1),
        ("G2", 1), ("B2", 1), ("D3", 1), ("G2", 1),
        ("C2", 3.5), ("R", 0.5),
    ]
    tb.add_melody(bass, "bass_bouncy", gain=0.34, start_beat=0.0, gate=0.76)
    tb.add_drum_pattern({
        "K": "X... ..x. X... ....",
        "S": ".... X... .... X.xx",
        "H": "x.x. x.x. x.x. x.o.",
    }, bars=7, gain=0.23)
    tb.mix(28.0, synth_drum("K", vel=1.0), 0.30)
    tb.mix(28.0, synth_drum("O", vel=1.0), 0.28)
    return tb.render()


def compose_defeat() -> np.ndarray:
    """Defeat Jingle (104 BPM, 20 beats, non-looping): Comic GBA sad wah-wah deflation."""
    tb = TrackBuilder(bpm=104.0, beats=20, loop=False)

    mel = [
        ("G4", 1.0), ("Gb4", 1.0), ("F4", 1.0), ("E4", 1.5), ("R", 0.5),
        ("Eb4", 0.75), ("D4", 0.75), ("C4", 1.5), ("R", 1.0),
        ("G4", 0.5), ("Eb4", 0.5), ("D4", 1.0), ("C4", 1.0), ("B3", 1.0),
        ("C4", 3.5), ("R", 1.5),
        ("R", 2.0),
    ]
    tb.add_melody(mel, "lead_flute", gain=0.30, start_beat=0.0, gate=0.88)

    bass = [
        ("C2", 2.0), ("B1", 2.0), ("Bb1", 2.0), ("A1", 2.0),
        ("Ab1", 2.0), ("G1", 2.0), ("C2", 3.5), ("R", 4.5),
    ]
    tb.add_melody(bass, "bass_bouncy", gain=0.30, start_beat=0.0, gate=0.78)
    tb.mix(12.0, synth_drum("S", vel=0.55), 0.16)
    tb.mix(12.5, synth_drum("C", vel=0.70), 0.18)
    return tb.render(target_rms=0.16)


MUSIC_RECIPES = {
    "bgm_overworld_desierto.wav": compose_overworld_desierto,
    "bgm_overworld_costa.wav": compose_overworld_costa,
    "bgm_overworld_bosque.wav": compose_overworld_bosque,
    "bgm_overworld_chiloe.wav": compose_overworld_chiloe,
    "bgm_battle_pila_ropa.wav": compose_battle_pila_ropa,
    "bgm_battle_gaviota.wav": compose_battle_gaviota,
    "bgm_battle_puma.wav": compose_battle_puma,
    "bgm_battle_caleuche.wav": compose_battle_caleuche,
    "bgm_victory.wav": compose_victory,
    "bgm_defeat.wav": compose_defeat,
}


# ---------------------------------------------------------------------------
# 61 Cohesive 8-bit / GBA Sound Effects (Base + Elements + Combos + Counters + UI)
# ---------------------------------------------------------------------------

def _norm_sfx(sig: np.ndarray, peak_target: float = 0.84) -> np.ndarray:
    sig = np.asarray(sig, dtype=np.float64)
    n = len(sig)
    fade_in = min(n, max(1, int(0.002 * SR)))
    fade_out = min(n, max(1, int(0.012 * SR)))
    sig[:fade_in] *= np.linspace(0.0, 1.0, fade_in)
    sig[-fade_out:] *= np.linspace(1.0, 0.0, fade_out)
    sig = np.tanh(sig * 1.1) / math.tanh(1.1)
    peak = float(np.max(np.abs(sig))) + 1e-9
    return sig * (peak_target / peak)


def _place(buf: np.ndarray, t_sec: float, seg: np.ndarray, gain: float = 1.0) -> None:
    i0 = int(round(t_sec * SR))
    if i0 >= len(buf) or i0 < 0:
        return
    i1 = min(len(buf), i0 + len(seg))
    buf[i0:i1] += seg[:i1 - i0] * gain


def _arp_seq(midis: list[float], step_sec: float, inst: str = "lead_bright", gate: float = 0.9, tail: float = 0.10) -> np.ndarray:
    total = int((len(midis) * step_sec + tail) * SR)
    buf = np.zeros(total, dtype=np.float64)
    for i, m in enumerate(midis):
        _place(buf, i * step_sec, synth_note(inst, m, step_sec * gate + tail * 0.4), 0.75)
    return buf


def build_all_sfx() -> dict[str, np.ndarray]:
    sfx: dict[str, np.ndarray] = {}

    # ---- A. 26 BASE SFX ----

    # 1. sfx_encounter_start: JRPG battle swoosh + rising 4-note GBA alarm
    n = int(0.68 * SR)
    t = np.arange(n) / SR
    buf = np.zeros(n)
    whoosh = one_pole_lowpass(lfsr_noise(n, 12000.0, seed=101), 2400.0) * np.sin(math.pi * t / 0.68) * 0.35
    buf += whoosh
    for i, m in enumerate([64, 68, 71, 76, 83]):
        _place(buf, 0.04 + i * 0.085, synth_note("brass_gba", m, 0.14 if i < 4 else 0.26), 0.72)
    sfx["sfx_encounter_start.wav"] = _norm_sfx(buf)

    # 2. sfx_rain_pour: 8-bit rain shower + playful water droplets
    n = int(0.75 * SR)
    t = np.arange(n) / SR
    rain = one_pole_highpass(one_pole_lowpass(lfsr_noise(n, 14000.0, seed=102), 4200.0), 900.0)
    env = np.sin(math.pi * np.clip(t / 0.75, 0, 1)) ** 0.5
    buf = rain * env * 0.55
    for i, dt in enumerate([0.08, 0.19, 0.31, 0.44, 0.56]):
        m = 78 + (i * 3) % 9
        _place(buf, dt, synth_note("bell_sparkle", m, 0.08), 0.32)
    sfx["sfx_rain_pour.wav"] = _norm_sfx(buf, 0.78)

    # 3. sfx_splat: cartoon squelch
    n = int(0.32 * SR)
    t = np.arange(n) / SR
    f = 340.0 * np.exp(-t * 14.0) + 75.0 + 45.0 * np.sin(2 * math.pi * 48 * t)
    sig = 0.6 * osc_pulse(f, n, 0.35) + 0.5 * one_pole_lowpass(lfsr_noise(n, 4500.0, seed=103), 1600.0)
    sfx["sfx_splat.wav"] = _norm_sfx(sig * np.exp(-t * 10.5))

    # 4. sfx_boing: iconic bouncy GBA spring
    n = int(0.38 * SR)
    t = np.arange(n) / SR
    f = (165.0 + 390.0 * (1.0 - np.exp(-t * 11.0))) * (1.0 + 0.09 * np.sin(2 * math.pi * 24.0 * t))
    sig = 0.65 * osc_pulse(f, n, 0.25) + 0.35 * osc_triangle(f, n)
    sfx["sfx_boing.wav"] = _norm_sfx(sig * np.exp(-t * 5.2))

    # 5. sfx_laugh: playful chiptune ha-ha-ha-ha!
    buf = np.zeros(int(0.58 * SR))
    for i, m in enumerate([74, 71, 69, 67, 64]):
        seg_n = int(0.085 * SR)
        tt = np.arange(seg_n) / SR
        ff = midi_to_hz(m) * (1.06 - 0.14 * tt / 0.085)
        _place(buf, i * 0.10, osc_pulse(ff, seg_n, 0.25) * exp_env(seg_n, 0.004, 16.0), 0.85)
    sfx["sfx_laugh.wav"] = _norm_sfx(buf)

    # 6. sfx_camera_flash: crisp shutter click + bright high shimmer
    buf = np.zeros(int(0.34 * SR))
    _place(buf, 0.0, synth_drum("C", 1.0, seed=6), 0.9)
    n2 = int(0.28 * SR)
    t2 = np.arange(n2) / SR
    shimmer = (
        0.5 * one_pole_highpass(lfsr_noise(n2, 16000.0, seed=106), 3400.0)
        + 0.4 * osc_sine(2400.0 + 900.0 * np.sin(2 * math.pi * 32 * t2), n2)
    ) * np.exp(-t2 * 13.0)
    _place(buf, 0.04, shimmer, 0.85)
    sfx["sfx_camera_flash.wav"] = _norm_sfx(buf)

    # 7. sfx_horn: comic clown/ship brassy honk-honk
    buf = np.zeros(int(0.46 * SR))
    for start, dur in [(0.0, 0.16), (0.20, 0.22)]:
        nn = int(dur * SR)
        tt = np.arange(nn) / SR
        sig = 0.55 * osc_saw(310.0, nn) + 0.45 * osc_pulse(324.0, nn, 0.30) + 0.25 * osc_pulse(465.0, nn, 0.25)
        _place(buf, start, sig * adsr_env(nn, 0.006, 0.04, 0.8, 0.03), 0.8)
    sfx["sfx_horn.wav"] = _norm_sfx(buf)

    # 8. sfx_rimshot: classic ba-dum-tss!
    buf = np.zeros(int(0.58 * SR))
    _place(buf, 0.00, synth_drum("S", 0.95, seed=1), 0.9)
    _place(buf, 0.13, synth_drum("T2", 0.95, seed=2), 0.85)
    _place(buf, 0.14, synth_drum("K", 0.80, seed=3), 0.65)
    n_cym = int(0.30 * SR)
    t_c = np.arange(n_cym) / SR
    cym = one_pole_highpass(lfsr_noise(n_cym, 16500.0, seed=108), 3800.0) * np.exp(-t_c * 11.0)
    _place(buf, 0.27, cym, 0.85)
    sfx["sfx_rimshot.wav"] = _norm_sfx(buf)

    # 9. sfx_meow_scared: startled high feline MRREOW!
    n = int(0.42 * SR)
    t = np.arange(n) / SR
    f = 620.0 + 780.0 * np.sin(math.pi * np.clip(t / 0.22, 0, 1)) - 420.0 * np.clip((t - 0.18) / 0.24, 0, 1)
    f *= 1.0 + 0.04 * np.sin(2 * math.pi * 28.0 * t)
    sig = 0.65 * osc_pulse(f, n, 0.20) + 0.35 * osc_saw(f, n)
    sfx["sfx_meow_scared.wav"] = _norm_sfx(sig * adsr_env(n, 0.012, 0.08, 0.72, 0.09))

    # 10. sfx_seagull: Valparaíso seagull KRA-KRA!
    buf = np.zeros(int(0.52 * SR))
    for start, dur, base in [(0.0, 0.21, 920.0), (0.25, 0.24, 1020.0)]:
        nn = int(dur * SR)
        tt = np.arange(nn) / SR
        f = base + 340.0 * np.sin(math.pi * tt / dur) - 260.0 * (tt / dur)
        sig = 0.65 * osc_pulse(f, nn, 0.16) + 0.25 * lfsr_noise(nn, 6000.0, short_mode=True, seed=110) * 0.35
        _place(buf, start, sig * adsr_env(nn, 0.015, 0.05, 0.7, 0.06), 0.85)
    sfx["sfx_seagull.wav"] = _norm_sfx(buf)

    # 11. sfx_cry_wah: comic sad trombone wah-waaah
    buf = np.zeros(int(0.68 * SR))
    for start, dur, f_hi, f_lo in [(0.0, 0.24, 440.0, 392.0), (0.27, 0.38, 370.0, 311.0)]:
        nn = int(dur * SR)
        tt = np.arange(nn) / SR
        f = np.linspace(f_hi, f_lo, nn) * (1.0 + 0.03 * np.sin(2 * math.pi * 7.5 * tt))
        sig = 0.65 * osc_pulse(f, nn, 0.40) + 0.35 * osc_triangle(f, nn)
        _place(buf, start, sig * adsr_env(nn, 0.015, 0.06, 0.75, 0.08), 0.85)
    sfx["sfx_cry_wah.wav"] = _norm_sfx(buf)

    # 12. water_rush: sweeping wave crash + bubbly splash
    n = int(0.62 * SR)
    t = np.arange(n) / SR
    noise = lfsr_noise(n, 13000.0, seed=112)
    wave_sig = one_pole_lowpass(noise, 2200.0) * (np.sin(math.pi * t / 0.62) ** 0.7)
    buf = wave_sig * 0.75
    for i, dt in enumerate([0.10, 0.18, 0.27, 0.36, 0.45]):
        nn = int(0.07 * SR)
        tt = np.arange(nn) / SR
        ff = (420.0 + i * 95.0) * (1.0 + 0.65 * tt / 0.07)
        _place(buf, dt, osc_sine(ff, nn) * exp_env(nn, 0.003, 24.0), 0.38)
    sfx["water_rush.wav"] = _norm_sfx(buf)

    # 13. bash_impact: punchy GBA comic hit
    buf = np.zeros(int(0.28 * SR))
    _place(buf, 0.0, synth_drum("K", 1.0, seed=13), 1.0)
    _place(buf, 0.005, synth_drum("S", 0.95, seed=14), 0.85)
    nn = int(0.14 * SR)
    tt = np.arange(nn) / SR
    _place(buf, 0.01, osc_pulse(520.0 * np.exp(-tt * 16.0) + 120.0, nn, 0.25) * np.exp(-tt * 18.0), 0.55)
    sfx["bash_impact.wav"] = _norm_sfx(buf)

    # 14. stomp: heavy ground slam
    n = int(0.36 * SR)
    t = np.arange(n) / SR
    sub = osc_triangle(125.0 * np.exp(-t * 14.0) + 34.0, n) * np.exp(-t * 8.5)
    rumble = one_pole_lowpass(lfsr_noise(n, 3800.0, seed=114), 700.0) * np.exp(-t * 12.0) * 0.55
    sfx["stomp.wav"] = _norm_sfx(sub + rumble)

    # 15. dog_bark: playful 8-bit woof-woof!
    buf = np.zeros(int(0.42 * SR))
    for start, base in [(0.0, 340.0), (0.19, 390.0)]:
        nn = int(0.14 * SR)
        tt = np.arange(nn) / SR
        f = base * (1.25 - 0.55 * (tt / 0.14))
        sig = 0.7 * osc_saw(f, nn) + 0.3 * one_pole_lowpass(lfsr_noise(nn, 4500.0, seed=115), 1400.0)
        _place(buf, start, sig * exp_env(nn, 0.004, 15.0), 0.9)
    sfx["dog_bark.wav"] = _norm_sfx(buf)

    # 16-18. chime_1, chime_2, chime_3 (ritual glowing arrows!)
    for idx, (m_bell, m_lead, dur) in enumerate([(72, 84, 0.24), (76, 88, 0.24), (79, 91, 0.28)], start=1):
        ch_buf = synth_note("bell_sparkle", m_bell, dur)
        _place(ch_buf, 0.0, synth_note("lead_bright", m_lead, dur * 0.5), 0.35)
        sfx[f"chime_{idx}.wav"] = _norm_sfx(ch_buf, 0.80 if idx < 3 else 0.82)

    # 19. parry_clash: metallic GBA clang
    n = int(0.32 * SR)
    t = np.arange(n) / SR
    sig = (
        0.50 * osc_sine(1420.0, n)
        + 0.40 * osc_sine(2170.0, n)
        + 0.35 * osc_pulse(3110.0, n, 0.125, max_harm=4)
        + 0.45 * one_pole_highpass(lfsr_noise(n, 14000.0, short_mode=True, seed=119), 2500.0) * np.exp(-t * 28.0)
    ) * np.exp(-t * 12.0)
    sfx["parry_clash.wav"] = _norm_sfx(sig)

    # 20. rock_fall: 3 cascading heavy thuds + gravel
    buf = np.zeros(int(0.56 * SR))
    for i, (dt, freq_s) in enumerate([(0.0, 120.0), (0.12, 95.0), (0.26, 78.0)]):
        nn = int(0.22 * SR)
        tt = np.arange(nn) / SR
        thud = osc_triangle(freq_s * np.exp(-tt * 12.0) + 32.0, nn) * np.exp(-tt * 11.0)
        gravel = one_pole_lowpass(lfsr_noise(nn, 5000.0, seed=120 + i), 1300.0) * np.exp(-tt * 14.0) * 0.55
        _place(buf, dt, thud + gravel, 0.85)
    sfx["rock_fall.wav"] = _norm_sfx(buf)

    # 21. orb_gain: crisp magical sparkle blip
    sfx["orb_gain.wav"] = _norm_sfx(_arp_seq([79, 84, 91], 0.042, "bell_sparkle", gate=0.95, tail=0.10), 0.78)

    # 22. sfx_spell_miss: friendly playful GBA low bonk
    buf = np.zeros(int(0.24 * SR))
    _place(buf, 0.0, synth_note("lead_bright", 52, 0.09), 0.75)
    _place(buf, 0.085, synth_note("lead_bright", 46, 0.13), 0.75)
    sfx["sfx_spell_miss.wav"] = _norm_sfx(buf, 0.74)

    # 23. sfx_spell_unleash: heroic rising starburst spell cast!
    buf = np.zeros(int(0.54 * SR))
    n_sw = int(0.32 * SR)
    t_sw = np.arange(n_sw) / SR
    sweep = osc_pulse(320.0 * (2.0 ** (t_sw * 5.2)), n_sw, 0.25) * np.exp(-t_sw * 4.5) * 0.45
    _place(buf, 0.0, sweep, 0.8)
    _place(buf, 0.02, _arp_seq([64, 68, 71, 76, 80, 83, 88], 0.048, "bell_sparkle", tail=0.16), 0.85)
    sfx["sfx_spell_unleash.wav"] = _norm_sfx(buf)

    # 24. heal: iconic warm JRPG healing sparkle arpeggio
    sfx["heal.wav"] = _norm_sfx(_arp_seq([65, 69, 72, 76, 77, 81, 84], 0.062, "bell_sparkle", tail=0.22), 0.82)

    # 25. puma_growl: dramatic theatrical FM feline roar
    n = int(0.55 * SR)
    t = np.arange(n) / SR
    mod = 42.0 * np.sin(2 * math.pi * 34.0 * t)
    f = (145.0 - 52.0 * (t / 0.55)) + mod
    sig = 0.65 * osc_saw(f, n, max_harm=12) + 0.35 * one_pole_lowpass(lfsr_noise(n, 4200.0, seed=125), 1400.0)
    sfx["puma_growl.wav"] = _norm_sfx(sig * adsr_env(n, 0.02, 0.08, 0.75, 0.14))

    # 26. hurt: classic retro Pudú damage oof
    n = int(0.26 * SR)
    t = np.arange(n) / SR
    f = 420.0 * np.exp(-t * 9.5) + 95.0
    buf = np.zeros(n)
    buf += 0.70 * osc_pulse(f, n, 0.25) * np.exp(-t * 11.0)
    _place(buf, 0.0, synth_drum("K", 0.85, seed=26), 0.65)
    sfx["hurt.wav"] = _norm_sfx(buf)

    # ---- B. 8 ELEMENTAL STAGE STATE SFX ----

    # 27. sfx_elem_mojado: splash + cheerful water plops
    buf = np.zeros(int(0.46 * SR))
    n1 = int(0.24 * SR)
    t1 = np.arange(n1) / SR
    _place(buf, 0.0, one_pole_lowpass(lfsr_noise(n1, 11000.0, seed=201), 2400.0) * np.exp(-t1 * 12.0), 0.65)
    for i, (dt, f0) in enumerate([(0.05, 520.0), (0.14, 680.0), (0.24, 820.0)]):
        nn = int(0.08 * SR)
        tt = np.arange(nn) / SR
        _place(buf, dt, osc_sine(f0 * (1.0 + 0.75 * tt / 0.08), nn) * exp_env(nn, 0.002, 22.0), 0.55)
    sfx["sfx_elem_mojado.wav"] = _norm_sfx(buf)

    # 28. sfx_elem_congelado: icy crystalline freeze chime + frost crackle
    buf = np.zeros(int(0.52 * SR))
    _place(buf, 0.0, _arp_seq([84, 88, 91, 95, 96], 0.045, "bell_sparkle", tail=0.20), 0.82)
    n_fr = int(0.28 * SR)
    t_fr = np.arange(n_fr) / SR
    frost = one_pole_highpass(lfsr_noise(n_fr, 16000.0, short_mode=True, seed=202), 4000.0) * np.exp(-t_fr * 14.0)
    _place(buf, 0.04, frost, 0.45)
    sfx["sfx_elem_congelado.wav"] = _norm_sfx(buf)

    # 29. sfx_elem_caliente: fiery ignition whoosh + crackling embers
    n = int(0.48 * SR)
    t = np.arange(n) / SR
    whoosh = one_pole_lowpass(lfsr_noise(n, 7500.0, seed=203), 1800.0) * (np.sin(math.pi * t / 0.48) ** 0.6)
    roar = osc_saw(130.0 + 180.0 * np.sin(math.pi * t / 0.48), n, max_harm=8) * np.exp(-t * 5.0) * 0.35
    buf = whoosh * 0.72 + roar
    for dt in [0.10, 0.19, 0.27, 0.35]:
        _place(buf, dt, synth_drum("H", 0.9, seed=int(dt * 100)), 0.45)
    sfx["sfx_elem_caliente.wav"] = _norm_sfx(buf)

    # 30. sfx_elem_enjabonado: playful rising soap-bubble pops!
    buf = np.zeros(int(0.50 * SR))
    for i, (dt, f0) in enumerate([(0.00, 420.0), (0.08, 560.0), (0.16, 710.0), (0.24, 890.0), (0.33, 1120.0)]):
        nn = int(0.075 * SR)
        tt = np.arange(nn) / SR
        ff = f0 * (1.0 + 0.95 * (tt / 0.075) ** 1.4)
        _place(buf, dt, osc_sine(ff, nn) * exp_env(nn, 0.002, 26.0), 0.75)
    sfx["sfx_elem_enjabonado.wav"] = _norm_sfx(buf)

    # 31. sfx_elem_aceitoso: slippery comic squelch-slide
    n = int(0.40 * SR)
    t = np.arange(n) / SR
    f = 260.0 + 360.0 * np.sin(2 * math.pi * 4.2 * t) * np.exp(-t * 2.5)
    sig = 0.6 * osc_triangle(f, n) + 0.4 * osc_pulse(f * 1.5, n, 0.35)
    sfx["sfx_elem_aceitoso.wav"] = _norm_sfx(sig * adsr_env(n, 0.01, 0.08, 0.7, 0.08))

    # 32. sfx_elem_oscuro: lights-out power-down sweep + eerie minor chime
    buf = np.zeros(int(0.54 * SR))
    n1 = int(0.32 * SR)
    t1 = np.arange(n1) / SR
    f = 680.0 * (2.0 ** (-t1 * 6.5))
    _place(buf, 0.0, osc_pulse(f, n1, 0.50) * np.exp(-t1 * 5.0), 0.70)
    _place(buf, 0.24, synth_note("organ_ghost", 57, 0.28), 0.55)
    _place(buf, 0.28, synth_note("bell_sparkle", 75, 0.24), 0.45)
    sfx["sfx_elem_oscuro.wav"] = _norm_sfx(buf)

    # 33. sfx_elem_ruidoso: comic megaphone/horn squawk + echo
    buf = np.zeros(int(0.52 * SR))
    for dt, g, f0 in [(0.0, 0.85, 580.0), (0.14, 0.60, 620.0), (0.28, 0.40, 580.0)]:
        nn = int(0.11 * SR)
        tt = np.arange(nn) / SR
        sig = 0.6 * osc_pulse(f0 * (1.0 + 0.08 * np.sin(2 * math.pi * 30 * tt)), nn, 0.20) + 0.4 * osc_saw(f0 * 1.03, nn)
        _place(buf, dt, sig * exp_env(nn, 0.004, 14.0), g)
    sfx["sfx_elem_ruidoso.wav"] = _norm_sfx(buf)

    # 34. sfx_elem_pegajoso: sticky stretchy glorp-pull!
    n = int(0.42 * SR)
    t = np.arange(n) / SR
    f = 190.0 + 220.0 * (t / 0.42) ** 1.6 + 65.0 * np.sin(2 * math.pi * 22.0 * t)
    sig = 0.65 * osc_pulse(f, n, 0.40) + 0.35 * one_pole_lowpass(lfsr_noise(n, 3200.0, seed=208), 1100.0)
    sfx["sfx_elem_pegajoso.wav"] = _norm_sfx(sig * adsr_env(n, 0.015, 0.06, 0.72, 0.07))

    # ---- C. 6 SUPER-COMBO SIGNATURE SFX ----

    # 35. sfx_combo_electro: crackling 8-bit thunderbolt + high-voltage arpeggio
    buf = np.zeros(int(0.72 * SR))
    n_z = int(0.48 * SR)
    t_z = np.arange(n_z) / SR
    zap_f = 950.0 + 750.0 * np.sign(np.sin(2 * math.pi * 46.0 * t_z))
    zap = (0.55 * osc_pulse(zap_f, n_z, 0.125) + 0.50 * one_pole_highpass(lfsr_noise(n_z, 15000.0, short_mode=True, seed=301), 1800.0))
    _place(buf, 0.0, zap * np.exp(-t_z * 5.5), 0.78)
    _place(buf, 0.05, _arp_seq([76, 80, 83, 88, 92, 95, 100], 0.055, "lead_bright", tail=0.22), 0.72)
    sfx["sfx_combo_electro.wav"] = _norm_sfx(buf)

    # 36. sfx_combo_deep_freeze: glacial shatter + crystalline victory chord
    buf = np.zeros(int(0.76 * SR))
    _place(buf, 0.0, synth_drum("K", 0.9, seed=302), 0.65)
    _place(buf, 0.03, _arp_seq([84, 88, 91, 96, 100, 103], 0.052, "bell_sparkle", tail=0.34), 0.90)
    n_sh = int(0.32 * SR)
    t_sh = np.arange(n_sh) / SR
    _place(buf, 0.08, one_pole_highpass(lfsr_noise(n_sh, 16000.0, short_mode=True, seed=303), 3600.0) * np.exp(-t_sh * 10.0), 0.55)
    sfx["sfx_combo_deep_freeze.wav"] = _norm_sfx(buf)

    # 37. sfx_combo_steam_sauna: pressurized tea-kettle whistle + hot steam blast
    buf = np.zeros(int(0.76 * SR))
    n_st = int(0.68 * SR)
    t_st = np.arange(n_st) / SR
    steam = one_pole_highpass(one_pole_lowpass(lfsr_noise(n_st, 15000.0, seed=304), 5200.0), 1200.0)
    _place(buf, 0.04, steam * (np.sin(math.pi * t_st / 0.68) ** 0.5), 0.68)
    n_wh = int(0.45 * SR)
    t_wh = np.arange(n_wh) / SR
    whistle = osc_sine(1280.0 + 460.0 * (t_wh / 0.45) + 28.0 * np.sin(2 * math.pi * 14 * t_wh), n_wh)
    _place(buf, 0.0, whistle * adsr_env(n_wh, 0.04, 0.06, 0.78, 0.12), 0.55)
    sfx["sfx_combo_steam_sauna.wav"] = _norm_sfx(buf)

    # 38. sfx_combo_slip_slide: cartoon slide-whistle zip + dizzy spin stars!
    buf = np.zeros(int(0.74 * SR))
    n_sl = int(0.42 * SR)
    t_sl = np.arange(n_sl) / SR
    f_sl = 380.0 + 1350.0 * np.sin(math.pi * (t_sl / 0.42) ** 0.85)
    _place(buf, 0.0, (0.7 * osc_sine(f_sl, n_sl) + 0.3 * osc_pulse(f_sl, n_sl, 0.50)) * adsr_env(n_sl, 0.01, 0.05, 0.85, 0.05), 0.78)
    _place(buf, 0.32, _arp_seq([81, 86, 81, 88, 81, 93], 0.05, "marimba", tail=0.14), 0.72)
    sfx["sfx_combo_slip_slide.wav"] = _norm_sfx(buf)

    # 39. sfx_combo_fire_boom: massive punchy 8-bit bomb explosion + fanfare punch
    buf = np.zeros(int(0.80 * SR))
    n_ex = int(0.74 * SR)
    t_ex = np.arange(n_ex) / SR
    boom = osc_triangle(160.0 * np.exp(-t_ex * 8.0) + 32.0, n_ex) * np.exp(-t_ex * 4.2)
    blast = one_pole_lowpass(lfsr_noise(n_ex, 6500.0, seed=306), 1900.0) * np.exp(-t_ex * 4.8)
    _place(buf, 0.0, 0.72 * boom + 0.85 * blast, 0.92)
    _place(buf, 0.06, _arp_seq([60, 67, 72, 79], 0.055, "brass_gba", tail=0.22), 0.48)
    sfx["sfx_combo_fire_boom.wav"] = _norm_sfx(buf)

    # 40. sfx_combo_chaos: wild glitch-arpeggio + spring + brass carnival chaos!
    buf = np.zeros(int(0.76 * SR))
    _place(buf, 0.0, _arp_seq([72, 78, 75, 83, 79, 87, 84, 91, 96], 0.048, "lead_bright", tail=0.20), 0.75)
    _place(buf, 0.14, sfx["sfx_boing.wav"], 0.45)
    _place(buf, 0.36, synth_drum("S", 1.0, seed=307), 0.65)
    _place(buf, 0.46, synth_note("brass_gba", 84, 0.24), 0.55)
    sfx["sfx_combo_chaos.wav"] = _norm_sfx(buf)

    # ---- D. 8 ENEMY COUNTERATTACK FX ----

    # 41. sfx_counter_tears
    buf = np.zeros(int(0.36 * SR))
    for i, dt in enumerate([0.0, 0.07, 0.14, 0.22]):
        nn = int(0.08 * SR)
        tt = np.arange(nn) / SR
        _place(buf, dt, osc_sine((880.0 - i * 90.0) * (1.0 - 0.35 * tt / 0.08), nn) * exp_env(nn, 0.002, 22.0), 0.75)
    sfx["sfx_counter_tears.wav"] = _norm_sfx(buf)

    # 42. sfx_counter_flash
    buf = np.zeros(int(0.30 * SR))
    n1 = int(0.24 * SR)
    t1 = np.arange(n1) / SR
    _place(buf, 0.0, osc_pulse(1600.0 * np.exp(-t1 * 7.0) + 480.0, n1, 0.125) * np.exp(-t1 * 12.0), 0.78)
    _place(buf, 0.02, one_pole_highpass(lfsr_noise(n1, 15000.0, seed=402), 3000.0) * np.exp(-t1 * 16.0), 0.60)
    sfx["sfx_counter_flash.wav"] = _norm_sfx(buf)

    # 43. sfx_counter_splash
    n = int(0.34 * SR)
    t = np.arange(n) / SR
    sig = one_pole_lowpass(lfsr_noise(n, 10500.0, seed=403), 2400.0) * np.exp(-t * 9.5)
    sig += osc_sine(360.0 + 380.0 * np.exp(-t * 14.0), n) * np.exp(-t * 15.0) * 0.45
    sfx["sfx_counter_splash.wav"] = _norm_sfx(sig)

    # 44. sfx_counter_wind
    n = int(0.40 * SR)
    t = np.arange(n) / SR
    env = np.sin(math.pi * t / 0.40) ** 0.8
    sig = one_pole_lowpass(lfsr_noise(n, 9500.0, seed=404), 1900.0) * env
    sig += osc_sine(310.0 + 260.0 * np.sin(math.pi * t / 0.40), n) * env * 0.25
    sfx["sfx_counter_wind.wav"] = _norm_sfx(sig)

    # 45. sfx_counter_mud
    n = int(0.34 * SR)
    t = np.arange(n) / SR
    f = 220.0 * np.exp(-t * 11.0) + 65.0 + 35.0 * np.sin(2 * math.pi * 36 * t)
    sig = 0.65 * osc_triangle(f, n) + 0.50 * one_pole_lowpass(lfsr_noise(n, 3600.0, seed=405), 1000.0)
    sfx["sfx_counter_mud.wav"] = _norm_sfx(sig * np.exp(-t * 9.5))

    # 46. sfx_counter_stink
    n = int(0.44 * SR)
    t = np.arange(n) / SR
    f = 290.0 - 110.0 * (t / 0.44) + 38.0 * np.sin(2 * math.pi * 9.5 * t)
    sig = 0.65 * osc_pulse(f, n, 0.35) + 0.35 * osc_saw(f * 0.99, n)
    sfx["sfx_counter_stink.wav"] = _norm_sfx(sig * adsr_env(n, 0.02, 0.06, 0.72, 0.10))

    # 47. sfx_counter_music
    buf = np.zeros(int(0.38 * SR))
    for m in [67, 73, 78]:  # cheeky dissonant tritone stab
        _place(buf, 0.0, synth_note("brass_gba", m, 0.16), 0.48)
    for m in [66, 72, 77]:
        _place(buf, 0.16, synth_note("brass_gba", m, 0.20), 0.48)
    sfx["sfx_counter_music.wav"] = _norm_sfx(buf)

    # 48. sfx_counter_sparkles
    sfx["sfx_counter_sparkles.wav"] = _norm_sfx(_arp_seq([86, 83, 89, 81, 86], 0.045, "bell_sparkle", tail=0.14), 0.80)

    # ---- E. COMBAT POLISH, UI & EXPLORATION SFX ----

    # 49. sfx_crit_hit: punchy GBA critical hit fanfare sting!
    buf = np.zeros(int(0.46 * SR))
    _place(buf, 0.0, synth_drum("K", 1.0, seed=49), 0.85)
    _place(buf, 0.0, synth_drum("S", 0.9, seed=50), 0.70)
    _place(buf, 0.02, _arp_seq([76, 83, 88, 95], 0.042, "bell_sparkle", tail=0.22), 0.85)
    _place(buf, 0.03, synth_note("brass_gba", 88, 0.24), 0.55)
    sfx["sfx_crit_hit.wav"] = _norm_sfx(buf)

    # 50. sfx_prompt_reject: playful referee whistle / double nope buzz
    buf = np.zeros(int(0.36 * SR))
    for start, m in [(0.0, 62), (0.14, 57)]:
        nn = int(0.13 * SR)
        tt = np.arange(nn) / SR
        ff = midi_to_hz(m) * (1.0 + 0.04 * np.sin(2 * math.pi * 24 * tt))
        _place(buf, start, osc_pulse(ff, nn, 0.35) * adsr_env(nn, 0.005, 0.04, 0.72, 0.03), 0.78)
    sfx["sfx_prompt_reject.wav"] = _norm_sfx(buf, 0.76)

    # 51. sfx_enemy_ko: dramatic cartoon spiral-out + triumphant pop!
    buf = np.zeros(int(0.70 * SR))
    n1 = int(0.42 * SR)
    t1 = np.arange(n1) / SR
    f1 = 880.0 * (2.0 ** (-t1 * 3.8)) * (1.0 + 0.08 * np.sin(2 * math.pi * 18.0 * t1))
    _place(buf, 0.0, osc_pulse(f1, n1, 0.25) * np.exp(-t1 * 3.0), 0.68)
    _place(buf, 0.36, synth_drum("K", 1.0, seed=51), 0.80)
    _place(buf, 0.38, _arp_seq([72, 76, 79, 84], 0.045, "bell_sparkle", tail=0.16), 0.80)
    sfx["sfx_enemy_ko.wav"] = _norm_sfx(buf)

    # 52. sfx_battle_enter: snappy JRPG arena dash-in whoosh
    n = int(0.34 * SR)
    t = np.arange(n) / SR
    env = np.sin(math.pi * t / 0.34)
    sig = one_pole_lowpass(lfsr_noise(n, 13000.0, seed=502), 2800.0) * env * 0.55
    sig += osc_pulse(260.0 + 520.0 * (t / 0.34), n, 0.25) * env * 0.45
    sfx["sfx_battle_enter.wav"] = _norm_sfx(sig, 0.78)

    # 53. sfx_ui_click: crisp GBA menu button tap
    buf = np.zeros(int(0.09 * SR))
    _place(buf, 0.0, synth_note("marimba", 81, 0.065), 0.85)
    sfx["sfx_ui_click.wav"] = _norm_sfx(buf, 0.72)

    # 54. sfx_prompt_open: friendly bright menu-open double blip
    sfx["sfx_prompt_open.wav"] = _norm_sfx(_arp_seq([76, 83], 0.048, "marimba", tail=0.07), 0.74)

    # 55. sfx_prompt_submit: energetic magical confirm chime
    sfx["sfx_prompt_submit.wav"] = _norm_sfx(_arp_seq([72, 79, 84], 0.046, "bell_sparkle", tail=0.12), 0.80)

    # 56. sfx_truck_jump: springy retro hop out of the Atacama lettuce truck
    n = int(0.24 * SR)
    t = np.arange(n) / SR
    f = 240.0 * (2.0 ** (t * 6.2))
    sig = 0.65 * osc_pulse(f, n, 0.25) + 0.35 * osc_triangle(f, n)
    sfx["sfx_truck_jump.wav"] = _norm_sfx(sig * np.exp(-t * 9.0), 0.76)

    # 57. sfx_truck_land: soft sandy hoof landing thump
    n = int(0.18 * SR)
    t = np.arange(n) / SR
    thud = osc_triangle(140.0 * np.exp(-t * 24.0) + 48.0, n) * np.exp(-t * 18.0)
    sand = one_pole_lowpass(lfsr_noise(n, 7000.0, seed=507), 1800.0) * np.exp(-t * 22.0) * 0.48
    sfx["sfx_truck_land.wav"] = _norm_sfx(thud + sand, 0.76)

    # 58. sfx_step_sand: gentle sandy hoof-tap (Atacama)
    n = int(0.065 * SR)
    t = np.arange(n) / SR
    sig = one_pole_lowpass(lfsr_noise(n, 9000.0, seed=508), 2200.0) * np.exp(-t * 58.0) * 0.70
    sig += osc_triangle(135.0, n) * np.exp(-t * 65.0) * 0.30
    sfx["sfx_step_sand.wav"] = _norm_sfx(sig, 0.62)

    # 59. sfx_step_wood: gentle hollow wooden pier hoof-tap (Valparaíso / Chiloé)
    n = int(0.065 * SR)
    t = np.arange(n) / SR
    sig = (0.65 * osc_triangle(285.0, n) + 0.35 * osc_sine(590.0, n)) * np.exp(-t * 62.0)
    sfx["sfx_step_wood.wav"] = _norm_sfx(sig, 0.64)

    # 60. sfx_step_grass: gentle leafy forest hoof-tap (Bosque Valdiviano)
    n = int(0.070 * SR)
    t = np.arange(n) / SR
    sig = one_pole_highpass(one_pole_lowpass(lfsr_noise(n, 11000.0, seed=510), 3400.0), 800.0) * np.exp(-t * 52.0)
    sig += osc_triangle(165.0, n) * np.exp(-t * 70.0) * 0.22
    sfx["sfx_step_grass.wav"] = _norm_sfx(sig, 0.60)

    # 61. sfx_camera_pan: subtle airy room-transition whoosh
    n = int(0.24 * SR)
    t = np.arange(n) / SR
    env = np.sin(math.pi * t / 0.24)
    sig = one_pole_lowpass(lfsr_noise(n, 7000.0, seed=511), 1500.0) * env * 0.55
    sig += osc_sine(440.0 + 180.0 * (t / 0.24), n) * env * 0.25
    sfx["sfx_camera_pan.wav"] = _norm_sfx(sig, 0.64)

    return sfx


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    total_bytes = 0

    print(f"Generating {len(MUSIC_RECIPES)} 8-bit/GBA music tracks into {OUT_DIR}...")
    for filename, fn in MUSIC_RECIPES.items():
        audio = fn()
        out_path = OUT_DIR / filename
        write_wav(out_path, audio)
        size = out_path.stat().st_size
        total_bytes += size
        print(f"  [BGM] {filename:30s}  {len(audio) / SR:5.2f}s  {size / 1024:7.1f} KB")

    sfx_map = build_all_sfx()
    print(f"Generating {len(sfx_map)} 8-bit/GBA SFX into {OUT_DIR}...")
    for filename, audio in sorted(sfx_map.items()):
        out_path = OUT_DIR / filename
        write_wav(out_path, audio)
        size = out_path.stat().st_size
        total_bytes += size
    print(f"Done! {len(MUSIC_RECIPES)} BGM + {len(sfx_map)} SFX generated ({total_bytes / (1024 * 1024):.2f} MB total).")


if __name__ == "__main__":
    main()
