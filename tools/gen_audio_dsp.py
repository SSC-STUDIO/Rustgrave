#!/usr/bin/env python3
"""Shared DSP helpers for tools/gen_audio_music.py and tools/gen_audio_sfx.py.

Project-original synthesis (numpy / scipy only) -> CC0, part of this project.
Everything is deterministic: each generator seeds its RNG from the asset name,
so re-running reproduces the same samples (only the OGG serial numbers differ).

Loop rule used by the music / bed generators: every oscillator frequency is
snapped to a multiple of 1/L (integer cycles per loop), every filter on a loop
runs on a 3x tiled copy (circular), every event wraps modulo the loop length and
reverb is an FFT circular convolution -- so the first and last sample of a loop
are neighbours in the *signal*, not just in the file.
"""
from __future__ import annotations

import hashlib
import os
import re
import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np
from scipy import signal

SR = 44100
ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"


# --- small utilities --------------------------------------------------------

def rng_for(name: str) -> np.random.Generator:
    digest = hashlib.sha1(name.encode("utf-8")).digest()
    return np.random.default_rng(int.from_bytes(digest[:8], "little"))


def db_to_lin(db: float) -> float:
    return float(10.0 ** (db / 20.0))


def lin_to_db(x: float) -> float:
    return float(20.0 * np.log10(max(abs(x), 1e-12)))


def midi_hz(m: float) -> float:
    return 440.0 * 2.0 ** ((m - 69.0) / 12.0)


def tt(n: int, sr: int = SR) -> np.ndarray:
    return np.arange(n) / float(sr)


def snap(freq: float, loop_seconds: float) -> float:
    """Nearest frequency with an integer number of cycles per loop."""
    return max(1.0, round(freq * loop_seconds)) / loop_seconds


def peak(x: np.ndarray) -> float:
    return float(np.max(np.abs(x))) if x.size else 0.0


def peak_db(x: np.ndarray) -> float:
    return lin_to_db(peak(x))


def normalize_peak(x: np.ndarray, target_db: float) -> np.ndarray:
    p = peak(x)
    if p <= 1e-9:
        return x
    return x * (db_to_lin(target_db) / p)


# --- filters ----------------------------------------------------------------

def _clip_fc(fc, sr: int):
    nyq = sr * 0.5
    if isinstance(fc, (list, tuple)):
        return [float(min(max(f, 8.0), nyq * 0.97)) for f in fc]
    return float(min(max(fc, 8.0), nyq * 0.97))


def sos_for(kind: str, fc, order: int = 2, sr: int = SR):
    return signal.butter(order, _clip_fc(fc, sr), btype=kind, fs=sr, output="sos")


def run_sos(x: np.ndarray, sos, circular: bool = False) -> np.ndarray:
    if circular:
        n = x.shape[-1]
        y = signal.sosfilt(sos, np.concatenate([x, x, x], axis=-1), axis=-1)
        return y[..., n:2 * n]
    return signal.sosfilt(sos, x, axis=-1)


def lp(x, fc, order=2, circular=False, sr=SR):
    return run_sos(x, sos_for("low", fc, order, sr), circular)


def hp(x, fc, order=2, circular=False, sr=SR):
    return run_sos(x, sos_for("high", fc, order, sr), circular)


def bp(x, lo, hi, order=2, circular=False, sr=SR):
    return run_sos(x, sos_for("band", [lo, hi], order, sr), circular)


def resonator(x, fc, q=20.0, circular=False, sr=SR):
    """Narrow band-pass (about fc/q wide) -- wind whistles, formants, ringing."""
    return bp(x, fc * (1.0 - 0.5 / q), fc * (1.0 + 0.5 / q), 2, circular, sr)


def tv_bandpass(x: np.ndarray, f_curve: np.ndarray, bw_oct: float = 1.2,
                order: int = 2, block: int = 128, sr: int = SR) -> np.ndarray:
    """Block-wise time-varying band-pass; the filter state is carried across blocks."""
    out = np.empty_like(x)
    zi = None
    half = 2.0 ** (bw_oct * 0.5)
    for s in range(0, len(x), block):
        e = min(s + block, len(x))
        fc = float(f_curve[min((s + e) // 2, len(f_curve) - 1)])
        sos = sos_for("band", [fc / half, fc * half], order, sr)
        if zi is None:
            zi = np.zeros((sos.shape[0], 2))
        out[s:e], zi = signal.sosfilt(sos, x[s:e], zi=zi)
    return out


def tv_lowpass(x: np.ndarray, f_curve: np.ndarray, order: int = 2,
               block: int = 128, sr: int = SR) -> np.ndarray:
    out = np.empty_like(x)
    zi = None
    for s in range(0, len(x), block):
        e = min(s + block, len(x))
        fc = float(f_curve[min((s + e) // 2, len(f_curve) - 1)])
        sos = sos_for("low", fc, order, sr)
        if zi is None:
            zi = np.zeros((sos.shape[0], 2))
        out[s:e], zi = signal.sosfilt(sos, x[s:e], zi=zi)
    return out


def saturate(x: np.ndarray, drive: float) -> np.ndarray:
    """tanh waveshaper normalised so small signals keep their level."""
    return np.tanh(drive * x) / np.tanh(drive)


def soft_limit(x: np.ndarray, ceiling: float = 0.89, knee: float = 0.7) -> np.ndarray:
    """Knee limiter: untouched below knee*ceiling, tanh-squashed above, never exceeds ceiling."""
    t = ceiling * knee
    a = np.abs(x)
    over = a > t
    if not over.any():
        return x
    y = x.copy()
    y[over] = np.sign(x[over]) * (t + (ceiling - t) * np.tanh((a[over] - t) / (ceiling - t)))
    return y


# --- noise & envelopes ------------------------------------------------------

def white(n: int, rng: np.random.Generator) -> np.ndarray:
    return rng.standard_normal(n)


def pink(n: int, rng: np.random.Generator) -> np.ndarray:
    w = rng.standard_normal(n)
    # Voss-ish via 1/f spectral shaping.
    spec = np.fft.rfft(w)
    f = np.fft.rfftfreq(n)
    f[0] = f[1] if len(f) > 1 else 1.0
    spec /= np.sqrt(f / f[1])
    out = np.fft.irfft(spec, n=n)
    return out / (np.std(out) + 1e-12)


def brown(n: int, rng: np.random.Generator) -> np.ndarray:
    w = rng.standard_normal(n)
    spec = np.fft.rfft(w)
    f = np.fft.rfftfreq(n)
    f[0] = f[1] if len(f) > 1 else 1.0
    spec /= (f / f[1])
    out = np.fft.irfft(spec, n=n)
    return out / (np.std(out) + 1e-12)


def exp_env(n: int, tau: float, sr: int = SR) -> np.ndarray:
    return np.exp(-np.arange(n) / (max(tau, 1e-4) * sr))


def attack_env(n: int, attack: float, sr: int = SR) -> np.ndarray:
    a = max(int(attack * sr), 1)
    e = np.ones(n)
    k = min(a, n)
    e[:k] = np.sin(np.linspace(0.0, np.pi / 2.0, k)) ** 2
    return e


def ad_env(n: int, attack: float, decay_tau: float, sr: int = SR) -> np.ndarray:
    return attack_env(n, attack, sr) * exp_env(n, decay_tau, sr)


def bump(n: int, center: float, width: float, sr: int = SR) -> np.ndarray:
    """Raised-cosine bump (seconds) -- swells and gusts."""
    t = tt(n, sr)
    x = np.clip((t - center) / max(width, 1e-4) + 0.5, 0.0, 1.0)
    return np.where((x > 0.0) & (x < 1.0), np.sin(np.pi * x) ** 2, 0.0)


def fade_edges(x: np.ndarray, fade_in: float = 0.002, fade_out: float = 0.008, sr: int = SR) -> np.ndarray:
    n = x.shape[-1]
    out = x.copy()
    a = min(int(fade_in * sr), n)
    r = min(int(fade_out * sr), n)
    if a > 0:
        out[..., :a] *= np.linspace(0.0, 1.0, a)
    if r > 0:
        out[..., n - r:] *= np.linspace(1.0, 0.0, r)
    return out


def sine_sweep(n: int, f0: float, f1: float, tau: float, sr: int = SR, phase: float = 0.0) -> np.ndarray:
    """Sine whose pitch glides f1 -> f0 with time constant tau (kick / thud body)."""
    t = tt(n, sr)
    f = f0 + (f1 - f0) * np.exp(-t / max(tau, 1e-4))
    return np.sin(phase + 2.0 * np.pi * np.cumsum(f) / sr)


def glide(n: int, f_start: float, f_end: float, sr: int = SR, curve: float = 1.0) -> np.ndarray:
    """Instantaneous-frequency curve (Hz per sample) between two values."""
    u = np.linspace(0.0, 1.0, n) ** curve
    return f_start + (f_end - f_start) * u


def osc_phase(f_curve: np.ndarray, sr: int = SR) -> np.ndarray:
    return 2.0 * np.pi * np.cumsum(f_curve) / sr


def saw_from_phase(phase: np.ndarray) -> np.ndarray:
    return 2.0 * ((phase / (2.0 * np.pi)) % 1.0) - 1.0


def square_from_phase(phase: np.ndarray) -> np.ndarray:
    return np.where(np.sin(phase) >= 0.0, 1.0, -1.0)


def partials(n: int, f0: float, ratios, amps, taus, sr: int = SR, phases=None, detune=0.0) -> np.ndarray:
    """Sum of decaying sines (bells, anvils, struck metal)."""
    t = tt(n, sr)
    out = np.zeros(n)
    for i, (r, a, tau) in enumerate(zip(ratios, amps, taus)):
        f = f0 * r
        if f >= sr * 0.45:
            continue
        ph = 0.0 if phases is None else phases[i]
        out += a * np.sin(2.0 * np.pi * f * t + ph) * np.exp(-t / max(tau, 1e-4))
        if detune:
            out += 0.6 * a * np.sin(2.0 * np.pi * f * (1.0 + detune) * t + ph + 0.7) * np.exp(-t / max(tau, 1e-4))
    return out


# --- stereo / placement -----------------------------------------------------

def pan_gains(p: float) -> tuple[float, float]:
    a = (np.clip(p, -1.0, 1.0) + 1.0) * np.pi / 4.0
    return float(np.cos(a)), float(np.sin(a))


def to_stereo(x: np.ndarray, p: float = 0.0) -> np.ndarray:
    if x.ndim == 2:
        return x
    l, r = pan_gains(p)
    return np.stack([x * l, x * r])


def place(buf: np.ndarray, sig: np.ndarray, start: int, gain: float = 1.0,
          pan: float = 0.0, wrap: bool = False) -> None:
    """Add sig into buf (mono or stereo) at sample index start; wrap=True folds
    the tail back to the beginning (seamless loops)."""
    s = sig if sig.ndim == buf.ndim else (to_stereo(sig, pan) if buf.ndim == 2 else sig.mean(axis=0))
    n = buf.shape[-1]
    m = s.shape[-1]
    start = int(start)
    if wrap:
        start %= n
        pos = 0
        while pos < m:
            cur = (start + pos) % n
            chunk = min(m - pos, n - cur)
            buf[..., cur:cur + chunk] += gain * s[..., pos:pos + chunk]
            pos += chunk
    else:
        if start >= n:
            return
        chunk = min(m, n - start)
        buf[..., start:start + chunk] += gain * s[..., :chunk]


# --- reverb -----------------------------------------------------------------

def reverb_ir(rt60: float, rng: np.random.Generator, sr: int = SR, predelay: float = 0.014,
              damping: float = 3200.0, length: float | None = None, early: int = 7,
              hf_decay: float = 0.42) -> np.ndarray:
    """Stereo noise-tail impulse response. Highs decay hf_decay x faster than lows."""
    length = length if length is not None else min(rt60 * 1.1, 14.0)
    n = int(length * sr)
    t = np.arange(n) / sr
    lo_sos = sos_for("low", damping, 2, sr)
    ir = np.zeros((2, n))
    pd = int(predelay * sr)
    for ch in range(2):
        w = rng.standard_normal(n)
        low = signal.sosfilt(lo_sos, w)
        high = w - low
        env_lo = np.exp(-6.9078 * t / rt60)
        env_hi = np.exp(-6.9078 * t / (rt60 * hf_decay))
        x = low * env_lo + 0.55 * high * env_hi
        x *= np.minimum(1.0, t / 0.015)
        ir[ch, pd:] = x[:n - pd]
    for _ in range(early):
        idx = pd + int(rng.uniform(0.006, 0.085) * sr)
        if idx < n:
            ir[:, idx] += rng.uniform(0.25, 0.7) * rng.choice([-1.0, 1.0], 2) * np.sqrt(np.sum(ir[0] ** 2) + 1e-9) * 0.02
    energy = np.sqrt(np.sum(ir ** 2, axis=1, keepdims=True)) + 1e-12
    return ir / energy


def reverb(x: np.ndarray, ir: np.ndarray, wet: float, circular: bool = False, dry: float = 1.0) -> np.ndarray:
    """Apply a stereo IR to the mono sum of x and mix with the dry signal (stereo out).

    circular=True: x is a loop; the tail wraps (IR must be shorter than x).
    circular=False: the output is extended by the IR length."""
    xs = to_stereo(x) if x.ndim == 1 else x
    mono = xs.mean(axis=0)
    n = mono.shape[-1]
    if circular:
        m = ir.shape[-1]
        if m > n:
            ir = ir[:, :n]
        spec = np.fft.rfft(mono)
        wet_sig = np.fft.irfft(spec[None, :] * np.fft.rfft(ir, n=n, axis=-1), n=n, axis=-1)
        # The IR has unit energy, so the wet RMS tracks the dry RMS for broadband input.
        return dry * xs + wet * wet_sig
    out_len = n + ir.shape[-1] - 1
    wet_sig = np.stack([signal.fftconvolve(mono, ir[c]) for c in range(2)])
    dry_sig = np.zeros((2, out_len))
    dry_sig[:, :n] = xs
    return dry * dry_sig + wet * wet_sig


# --- wav / ogg / loudness ---------------------------------------------------

def write_wav(path: Path, x: np.ndarray, sr: int = SR) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = np.clip(x, -1.0, 1.0)
    pcm = np.round(data * 32767.0).astype("<i2")
    ch = 1 if data.ndim == 1 else data.shape[0]
    inter = pcm if ch == 1 else pcm.T.reshape(-1)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(inter.tobytes())


def read_audio(path: Path, sr: int = SR, channels: int = 2) -> np.ndarray:
    """Decode any file through ffmpeg to float32 (channels, n)."""
    cmd = ["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-ac", str(channels), "-ar", str(sr), "-"]
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    arr = np.frombuffer(raw, dtype="<f4").reshape(-1, channels).T
    return arr.astype(np.float64)


def encode_ogg(x: np.ndarray, path: Path, quality: float = 3.0, sr: int = SR) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "in.wav"
        write_wav(wav, x, sr)
        cmd = ["ffmpeg", "-y", "-v", "error", "-i", str(wav), "-map_metadata", "-1",
               "-c:a", "libvorbis", "-q:a", str(quality), "-ar", str(sr), str(path)]
        subprocess.run(cmd, check=True)


_I_RE = re.compile(r"\bI:\s+(-?[\d.]+|-inf)\s+LUFS")
_PEAK_RE = re.compile(r"Peak:\s+(-?[\d.]+|-inf)\s+dBFS")
_LRA_RE = re.compile(r"LRA:\s+(-?[\d.]+)\s+LU")


def measure_file(path: Path) -> dict:
    cmd = ["ffmpeg", "-nostats", "-hide_banner", "-i", str(path), "-af", "ebur128=peak=true", "-f", "null", "-"]
    err = subprocess.run(cmd, capture_output=True, text=True).stderr
    summary = err[err.rfind("Summary:"):] if "Summary:" in err else err
    i = _I_RE.findall(summary)
    p = _PEAK_RE.findall(summary)
    r = _LRA_RE.findall(summary)
    to_f = lambda v: float("-inf") if v == "-inf" else float(v)
    return {"lufs": to_f(i[-1]) if i else float("-inf"),
            "true_peak": to_f(p[-1]) if p else float("-inf"),
            "lra": float(r[-1]) if r else 0.0}


def measure(x: np.ndarray, sr: int = SR) -> dict:
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "m.wav"
        write_wav(wav, x, sr)
        return measure_file(wav)


def normalize_lufs(x: np.ndarray, target: float, max_peak_db: float = -1.5, sr: int = SR) -> np.ndarray:
    """Linear gain to the target integrated loudness (ffmpeg ebur128). The measurement runs on a
    clip-free copy (peak 0.25); if the result would exceed max_peak_db a knee limiter catches the
    peaks and the gain is re-trimmed so the limited signal still lands on the target."""
    p = peak(x)
    if p <= 1e-9:
        return x
    pre = 0.25 / p
    m = measure(x * pre, sr)
    if not np.isfinite(m["lufs"]):
        return x
    gain_db = target - m["lufs"] + lin_to_db(pre)
    ceiling = db_to_lin(max_peak_db)
    z = x
    for _ in range(4):
        z = soft_limit(x * db_to_lin(gain_db), ceiling)
        mz = measure(z, sr)
        if not np.isfinite(mz["lufs"]):
            break
        err = target - mz["lufs"]
        if abs(err) < 0.1:
            break
        gain_db += err
    return z


def sub_cut(x: np.ndarray, fc: float = 38.0, circular: bool = False) -> np.ndarray:
    """Keep sustained content under ~35 Hz out of every asset (speaker-safe, mix-safe)."""
    return hp(x, fc, 4, circular)
