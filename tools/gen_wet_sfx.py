#!/usr/bin/env python3
"""Procedural CC0 splash one-shot + nest-steam bed for Rustgrave.

The splash is unchanged (byte-identical to the previous file: same generator,
same seed, deterministic stdlib RNG). The looping nest_hiss bed was rebuilt on a
circle (numpy): the noise is filtered on a 3x tiled copy so the one-pole state
wraps, the steam pops fold back with modulo indexing and the breath LFO uses an
integer number of cycles per loop, so the file edge is continuous. Its level is
normalized to the measured RMS of the replaced file (-19.6 dBFS), keeping
AMBIENCE_LEVEL["nest_hiss"] = 0.20 unchanged.

usage: python tools/gen_wet_sfx.py [--check]
"""
from __future__ import annotations

import argparse
import math
import random
import struct
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
AUDIO = ROOT / "assets" / "audio"
SR = 22050
TWO_PI = 2.0 * np.pi
N = int(SR * 2.4)      # nest_hiss loop length


# --- splash (unchanged, stdlib) --------------------------------------------

def _clamp(v: float) -> int:
    return max(-32767, min(32767, int(v)))


def _write(path: Path, samples: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "w") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(b"".join(struct.pack("<h", _clamp(s * 32767.0)) for s in samples))


def _splash(seed: int) -> list[float]:
    rng = random.Random(seed)
    n = int(SR * 0.16)
    brown = 0.0
    hiss = 0.0
    samples: list[float] = []
    for i in range(n):
        white = rng.uniform(-1.0, 1.0)
        brown = brown * 0.97 + white * 0.03
        hiss = hiss * 0.55 + white * 0.45
        t = i / float(SR)
        thud = math.sin(2.0 * math.pi * 62.0 * t) * math.exp(-t * 28.0) * 0.55
        slap = math.sin(2.0 * math.pi * 210.0 * t) * math.exp(-t * 38.0) * 0.28
        spray = hiss * math.exp(-t * 22.0) * 0.42
        body = brown * math.exp(-t * 18.0) * 0.35
        samples.append(thud + slap + spray + body)
    peak = max(0.001, max(abs(x) for x in samples))
    return [x * (0.55 / peak) for x in samples]


# --- nest steam bed (circular, numpy) --------------------------------------

def _leaky_circular(white: np.ndarray, coef: float, gain: float) -> np.ndarray:
    w = np.tile(white, 3)
    y = np.empty(w.size)
    acc = 0.0
    for i, v in enumerate(w):
        acc = acc * coef + v * gain
        y[i] = acc
    return y[N:2 * N]


def _nest_hiss(seed: int, rms_db: float = -19.6) -> np.ndarray:
    rng = np.random.default_rng(seed)
    white = rng.uniform(-1.0, 1.0, N)
    brown = _leaky_circular(white, 0.984, 0.016)
    hiss = _leaky_circular(white, 0.58, 0.42)
    mid = _leaky_circular(white, 0.90, 0.10)
    breath = 0.82 + 0.18 * np.sin(TWO_PI * np.arange(N) / N)      # 1 cycle / 2.4 s
    steam = hiss * 0.48 + mid * 0.18
    ember = brown * 0.22
    x = (steam + ember) * breath
    length = int(0.05 * SR)
    d = np.arange(length)
    for _ in range(18):
        start = int(rng.integers(0, N))
        a = rng.uniform(0.04, 0.11)
        tau = rng.uniform(40.0, 90.0)
        shape = a * np.exp(-d / tau) * np.where(d % 2, 0.7, 0.35)
        np.add.at(x, (start + d) % N, shape)
    x -= x.mean()
    return x * (10.0 ** (rms_db / 20.0) / (np.sqrt(np.mean(x * x)) + 1e-12))


def _write_np(path: Path, x: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = np.round(np.clip(x, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(data.tobytes())


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="only print the float-array seam stats")
    args = ap.parse_args()
    splash = _splash(0x53504C31)
    hiss = _nest_hiss(0x4E535431)
    seam = float(abs(hiss[0] - hiss[-1]))
    print(f"nest_hiss      {N / SR:4.2f}s  rms {20 * np.log10(np.sqrt(np.mean(hiss * hiss))):6.1f} dBFS"
          f"  peak {20 * np.log10(np.max(np.abs(hiss))):6.1f} dBFS  join {seam:.2e} (circular)")
    if not args.check:
        _write(AUDIO / "sfx" / "splash.wav", splash)
        _write_np(AUDIO / "ambience" / "nest_hiss.wav", hiss)
        print(f"  -> {AUDIO / 'sfx' / 'splash.wav'}")
        print(f"  -> {AUDIO / 'ambience' / 'nest_hiss.wav'}")


if __name__ == "__main__":
    main()
