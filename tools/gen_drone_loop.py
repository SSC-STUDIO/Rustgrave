#!/usr/bin/env python3
"""Procedural CC0 cemetery drone for Rustgrave (numpy only).

The old version summed 46 / 69.2 / 92.5 Hz sines on a 4 s loop: 69.2 Hz is not an
integer number of cycles per loop, so the file edge was a hard phase jump (a
measured -16.7 dBFS discontinuity, ~60x the file's own largest step: an audible
click every 4 s). This version:

  * snaps every oscillator to an integer number of cycles per loop,
  * gives the 8 s breath LFO exactly one cycle per loop (old period was 8.98 s),
  * uses an 8 s loop so the swell does not repeat twice as often as before.

Deterministic and idempotent by construction (pure sines, no RNG), and
bit-continuous across the loop point.
Level: normalized to the measured RMS of the replaced file (-24.3 dBFS), so the
AMBIENCE_LEVEL["cemetery"] = 0.28 mix does not change.

usage: python tools/gen_drone_loop.py [--check]
"""
from __future__ import annotations

import argparse
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "audio" / "ambience" / "cemetery_drone.wav"
SR = 22050
SECONDS = 8.0
N = int(SR * SECONDS)
TWO_PI = 2.0 * np.pi
RMS_DB = -24.3                            # measured RMS of the replaced 4 s file


def _snap(freq: float, loop: float) -> float:
    """Nearest frequency with an integer number of cycles per loop."""
    return max(1.0, round(freq * loop)) / loop


def _drone() -> np.ndarray:
    t = np.arange(N) / float(SR)
    f1 = _snap(46.0, SECONDS)          # 46.0 Hz -> 368 cycles / 8 s
    f2 = _snap(69.2, SECONDS)          # 69.2 Hz -> 554 cycles / 8 s (was not periodic at 4 s)
    f3 = _snap(92.5, SECONDS)          # 92.5 Hz -> 740 cycles / 8 s
    a = 0.11 * np.sin(TWO_PI * f1 * t)
    b = 0.07 * np.sin(TWO_PI * f2 * t + 0.4)
    c = 0.04 * np.sin(TWO_PI * f3 * t + 1.1)
    breath = 0.82 + 0.18 * np.sin(TWO_PI * t / SECONDS)   # 1 cycle / 8 s ~= old 8.98 s
    x = (a + b + c) * breath
    x -= x.mean()
    gain = 10.0 ** (RMS_DB / 20.0) / (np.sqrt(np.mean(x * x)) + 1e-12)
    return x * gain


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
    x = _drone()
    seam = float(abs(x[0] - x[-1]))
    print(f"{OUT.name:<20} {N / SR:4.2f}s  rms {20 * np.log10(np.sqrt(np.mean(x * x))):6.1f} dBFS"
          f"  peak {20 * np.log10(np.max(np.abs(x))):6.1f} dBFS  join {seam:.2e} (integer cycles/loop)")
    if not args.check:
        _write(OUT, x)
        print(f"  -> {OUT}")


if __name__ == "__main__":
    main()
