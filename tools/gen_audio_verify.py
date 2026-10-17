#!/usr/bin/env python3
"""Numeric mix verification for the generated audio (nobody can listen in CI).

For every OGG / WAV under assets/audio (except the legacy weather loops) prints:
  seconds, integrated LUFS, true peak, size, level under 35 Hz and above 8 kHz (dBFS),
and for loops the seam test on the *decoded* file: 50 ms RMS before / after the loop
point (dB jump) and the sample step at the seam relative to the local step RMS.
--png writes ffmpeg showspectrumpic images into the given directory.

usage: python tools/gen_audio_verify.py [--only substring] [--png DIR]
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_audio_dsp import SR, ASSETS, read_audio, measure_file, hp, lp, bp

LEGACY = {"rain", "rust_rain", "cemetery_drone", "nest_hiss", "splash"}
LOOP_DIRS = ("music", "ambience")


def dbfs(x: float) -> float:
    return 20.0 * np.log10(max(x, 1e-9))


def rms(a: np.ndarray) -> float:
    return float(np.sqrt(np.mean(a * a))) + 1e-12


def is_loop(path: Path) -> bool:
    if path.parent.name == "ambience":
        return path.stem.startswith("bed_")
    return path.parent.name == "music" and not path.stem.startswith("stinger_")


def analyse(path: Path) -> dict:
    m = measure_file(path)
    x = read_audio(path, SR, 2)
    mono = x.mean(axis=0)
    out = {"file": f"{path.parent.name}/{path.name}", "sec": mono.size / SR, "lufs": m["lufs"], "tp": m["true_peak"],
           "kb": path.stat().st_size / 1024.0}
    low = bp(mono, 15.0, 35.0, 2)
    high = hp(mono, 8000.0, 2)
    out["sub35"] = dbfs(rms(low))
    out["hi8k"] = dbfs(rms(high))
    w = int(0.05 * SR)
    hi_blocks = [rms(high[i:i + w]) for i in range(0, max(1, high.size - w), w)]
    out["hi8k_p99"] = dbfs(float(np.percentile(hi_blocks, 99)))
    if is_loop(path):
        y = np.concatenate([x, x], axis=1)
        n = x.shape[1]
        before, after = rms(y[:, n - w:n]), rms(y[:, n:n + w])
        out["seam_db"] = dbfs(after) - dbfs(before)
        seg = np.diff(y[:, n - 2205:n + 2205], axis=1)
        out["seam_step"] = float(np.abs(y[:, n] - y[:, n - 1]).max() / (rms(seg) + 1e-9))
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--png", default="")
    args = ap.parse_args()
    files = []
    for sub in ("music", "ambience", "sfx"):
        for ext in ("*.ogg", "*.wav"):
            files += sorted((ASSETS / "audio" / sub).glob(ext))
    files = [f for f in files if f.stem not in LEGACY and args.only in f.name]
    total = 0.0
    print(f"{'file':<36}{'sec':>6}{'LUFS':>7}{'TP':>6}{'<35Hz':>7}{'>8k':>6}{'>8kP99':>7}{'seam':>6}{'step':>6}{'KB':>6}")
    for f in files:
        r = analyse(f)
        total += r["kb"]
        seam = f"{r['seam_db']:6.2f}" if "seam_db" in r else "     -"
        step = f"{r['seam_step']:6.2f}" if "seam_step" in r else "     -"
        print(f"{r['file']:<36}{r['sec']:6.2f}{r['lufs']:7.1f}{r['tp']:6.1f}{r['sub35']:7.1f}{r['hi8k']:6.1f}{r['hi8k_p99']:7.1f}{seam}{step}{r['kb']:6.0f}")
        if args.png:
            Path(args.png).mkdir(parents=True, exist_ok=True)
            png = Path(args.png) / (f.stem + ".png")
            subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(f), "-lavfi",
                            "showspectrumpic=s=900x400:legend=1:scale=log:fscale=log:start=30:stop=16000", str(png)])
    print(f"total {total / 1024:.1f} MB over {len(files)} files")


if __name__ == "__main__":
    main()
