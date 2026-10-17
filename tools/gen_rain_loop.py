#!/usr/bin/env python3
"""Procedural CC0 rain loops for Rustgrave (numpy only).

Original design, but every layer is now built on a *circle*: the noise is filtered
on a 3x tiled copy (the one-pole state wraps around the loop point), the drop
tails are folded back with modulo indexing and the breath LFO uses an integer
number of cycles per loop. The file's last sample is therefore adjacent to its
first sample in the signal, not just in the file: no crossfade, no seam.

Deterministic (a fixed seed per file -> byte-identical .wav) and idempotent.
AMBIENCE_LEVEL["rain"] / ["rust_rain"] = 0.28, so the loudness here is mix
critical: the RMS targets below are the measured RMS of the previous
crossfaded files (rain -20.8 dBFS, rust_rain -21.4 dBFS).

usage: python tools/gen_rain_loop.py [--check]
"""
from __future__ import annotations

import argparse
import hashlib
import sys
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "audio" / "ambience"
SR = 22050                 # legacy sample rate: background beds, keeps the WAV small
SECONDS = 3.0
N = int(SR * SECONDS)
TWO_PI = 2.0 * np.pi

# (seed, rust, peak/rms target dBFS) -- keep the two plates in the same family.
PLATES = {
    "rain.wav": (0x52535431, False, -20.8),
    "rust_rain.wav": (0x52535432, True, -21.4),
}


def _seed(text: str) -> np.random.Generator:
    digest = hashlib.sha1(text.encode("utf-8")).digest()
    return np.random.default_rng(int.from_bytes(digest[:8], "little"))


def _leaky_circular(white: np.ndarray, coef: float, gain: float) -> np.ndarray:
    """One-pole y[i] = y[i-1]*coef + white[i]*gain, periodic over N.

    Running it over three tiled copies and keeping the middle copy makes the
    filter state at sample 0 the state it would have after the last sample, so
    the loop point is indistinguishable from any other sample boundary.
    """
    w = np.tile(white, 3)
    y = np.empty(w.size)
    acc = 0.0
    for i, v in enumerate(w):
        acc = acc * coef + v * gain
        y[i] = acc
    return y[N:2 * N]


def _drops(rng: np.random.Generator, count: int,
           amp: tuple[float, float], decay: tuple[float, float], level: float) -> np.ndarray:
    """Rain patter: short decaying noise bursts folded around the loop point."""
    out = np.zeros(N)
    length = int(0.08 * SR)
    d = np.arange(length)
    for _ in range(count):
        start = int(rng.integers(0, N))
        a = level * rng.uniform(*amp)
        tau = rng.uniform(*decay)
        shape = a * np.exp(-d / tau) * np.where(d % 3, 1.0, 0.45)
        idx = (start + d) % N
        np.add.at(out, idx, shape)
    return out


def _rain(seed: int, rust: bool, rms_db: float) -> np.ndarray:
    rng = _seed(f"rain:{seed}:{rust}")
    white = rng.uniform(-1.0, 1.0, N)
    # leaky-integrator brown body + bright hiss + patter, exactly the old set.
    brown = _leaky_circular(white, 0.986, 0.014)
    hiss = _leaky_circular(white, 0.62, 0.38)
    mid = _leaky_circular(white, 0.88, 0.12)
    # Breath: one integer cycle per loop (old 0.27 Hz over an 8.98 s period -> 0.33 Hz).
    breath = 0.86 + 0.14 * np.sin(TWO_PI * np.arange(N) / N)
    body = brown * (0.55 if rust else 0.32)
    spray = hiss * (0.22 if rust else 0.42)
    patter = mid * (0.28 if rust else 0.18)
    acc = (body + spray + patter) * breath
    acc += _drops(rng, 90 if rust else 70, (0.08, 0.22), (80.0, 240.0), 1.0)
    acc -= acc.mean()                              # a DC offset in a bed is drift, not mood
    gain = 10.0 ** (rms_db / 20.0) / (np.sqrt(np.mean(acc * acc)) + 1e-12)
    return acc * gain


def _write(path: Path, x: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = np.round(np.clip(x, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SR)
        wav.writeframes(data.tobytes())


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="only print the float-array seam stats")
    args = ap.parse_args()
    for name, (seed, rust, rms_db) in PLATES.items():
        x = _rain(seed, rust, rms_db)
        seam = float(abs(x[0] - x[-1]))
        print(f"{name:<14} {N / SR:4.2f}s  rms {20 * np.log10(np.sqrt(np.mean(x * x))):6.1f} dBFS"
              f"  peak {20 * np.log10(np.max(np.abs(x))):6.1f} dBFS  join {seam:.2e} (no crossfade)")
        if not args.check:
            _write(OUT / name, x)
            print(f"  -> {OUT / name}")


if __name__ == "__main__":
    main()
