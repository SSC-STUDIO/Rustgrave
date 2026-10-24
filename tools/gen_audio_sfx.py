#!/usr/bin/env python3
"""Procedural one-shots + ambience beds for Rustgrave (project-original, CC0).

Writes 16-bit mono 44.1 kHz WAV into assets/audio/sfx/ and OGG loops into
assets/audio/ambience/bed_*.ogg. Every one-shot is normalised to a stated peak
(never above -3 dBFS) and carries no sustained content under ~35 Hz.
A handful of sounds layer processed Kenney CC0 recordings (door_open); those
sources are listed in assets/external/CREDITS.md (Audio section).

usage: python tools/gen_audio_sfx.py [--only substring] [--no-beds]
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import numpy as np
from scipy import signal

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_audio_dsp import (SR, ASSETS, rng_for, midi_hz, tt, peak, lp, hp, bp, resonator, tv_bandpass, tv_lowpass,
                           saturate, white, pink, brown, attack_env, exp_env, sine_sweep, glide, osc_phase,
                           saw_from_phase, partials, reverb_ir, write_wav, read_audio, encode_ogg, fade_edges,
                           normalize_lufs, sub_cut, db_to_lin, measure, to_stereo)
from gen_audio_music import wind, roar, hum, drone, finish_loop, mix_in, bell_note, kick as music_kick

SFX = ASSETS / "audio" / "sfx"
AMB = ASSETS / "audio" / "ambience"
KENNEY = ASSETS / "external" / "kenney" / "Audio (295 files)" / "RPG sounds (50 sounds)"
TAU = 2.0 * np.pi


# --- building blocks --------------------------------------------------------

def nn(sec: float) -> int:
    return int(sec * SR)


def add(buf: np.ndarray, sig: np.ndarray, t: float = 0.0, gain: float = 1.0) -> None:
    i = int(t * SR)
    if i >= len(buf) or i < 0:
        return
    m = min(len(sig), len(buf) - i)
    buf[i:i + m] += gain * sig[:m]


def pk(x: np.ndarray) -> np.ndarray:
    return x / (peak(x) + 1e-9)


def rn(x: np.ndarray) -> np.ndarray:
    return x / (float(np.sqrt(np.mean(x * x))) + 1e-9)


def _unit(y: np.ndarray) -> np.ndarray:
    return y / (float(np.sqrt(np.mean(y * y))) + 1e-9)


def bpn(x, lo, hi, order=2, circular=False):
    """Band-passed noise at unit RMS (layer gains then mean what they say)."""
    return _unit(bp(x, lo, hi, order, circular))


def lpn(x, fc, order=2, circular=False):
    return _unit(lp(x, fc, order, circular))


def hpn(x, fc, order=2, circular=False):
    return _unit(hp(x, fc, order, circular))


def thump(rng, f_hi=140.0, f_lo=55.0, tau_p=0.03, decay=0.1, dur=0.4, drive=1.0) -> np.ndarray:
    n = nn(dur)
    x = sine_sweep(n, f_lo, f_hi, tau_p) * attack_env(n, 0.0015) * exp_env(n, decay)
    return pk(saturate(x * 1.4, drive + 0.6)) if drive > 0 else pk(x)


def crack(rng, dur=0.08, lo=1500.0, hi=6000.0, tau=0.008) -> np.ndarray:
    n = nn(dur)
    return pk(bp(white(n, rng), lo, hi) * exp_env(n, tau) * attack_env(n, 0.0004))


def ring(f0, ratios, amps, taus, dur, detune=0.0) -> np.ndarray:
    return partials(nn(dur), f0, ratios, amps, taus, detune=detune)


def window(n: int, attack: float, tau: float) -> np.ndarray:
    return attack_env(n, attack) * exp_env(n, tau)


def whoosh(rng, dur, f0, f1, f2, bw=1.6, peak_at=0.45, power=2.0) -> np.ndarray:
    n = nn(dur)
    u = np.linspace(0.0, 1.0, n)
    f = np.where(u < peak_at, f0 * (f1 / f0) ** (u / peak_at), f1 * (f2 / f1) ** ((u - peak_at) / (1.0 - peak_at)))
    x = tv_bandpass(white(n, rng), f, bw_oct=bw)
    a = np.clip(u / peak_at, 0.0, 1.0)
    b = np.clip((u - peak_at) / (1.0 - peak_at), 0.0, 1.0)
    win = np.where(u < peak_at, np.sin(0.5 * np.pi * a) ** power, np.cos(0.5 * np.pi * b) ** (power * 1.2))
    return rn(x) * win


def armor(rng, count=2, span=0.05, gain=1.0) -> np.ndarray:
    """Tiny plate / buckle jingle that rides on a heavy knight's footfalls."""
    n = nn(span + 0.08)
    out = np.zeros(n)
    for _ in range(count):
        f = rng.uniform(1600.0, 4200.0)
        t0 = rng.uniform(0.0, span)
        k = ring(f, [1.0, 2.31], [1.0, 0.5], [0.025, 0.012], 0.12)
        add(out, k, t0, rng.uniform(0.5, 1.0))
    return pk(out) * gain


def grit(rng, dur, count, lo, hi, tau=0.01) -> np.ndarray:
    n = nn(dur)
    out = np.zeros(n)
    for _ in range(count):
        add(out, crack(rng, 0.04, lo, hi, tau), rng.uniform(0.0, dur * 0.9), rng.uniform(0.25, 1.0))
    return pk(out)


def bubble(rng, f0, f1, dur=0.07) -> np.ndarray:
    n = nn(dur)
    return np.sin(osc_phase(glide(n, f0, f1))) * exp_env(n, dur * 0.35) * attack_env(n, 0.002)


def mono_reverb(x: np.ndarray, rng, rt60: float, wet: float, damping: float = 3200.0, tail: float = 0.0) -> np.ndarray:
    """Room tail on a mono one-shot; the output keeps only `tail` seconds (default 0.45 x rt60)
    past the dry sound -- finish() fades the cut, and one-shots must stay short."""
    ir = reverb_ir(rt60, rng, damping=damping)
    w = signal.fftconvolve(x, ir[0])
    keep = min(len(w), len(x) + int((tail if tail > 0.0 else rt60 * 0.45) * SR))
    out = np.zeros(keep)
    out[:len(x)] += x
    return out + wet * w[:keep]


def finish(x: np.ndarray, peak_db: float, hp_hz: float = 32.0, fade: float = 0.012, lp_hz: float = 14000.0) -> np.ndarray:
    x = x - np.mean(x)
    x = hp(x, hp_hz, 2)
    x = lp(x, lp_hz, 2)
    x = fade_edges(x, 0.0008, fade)
    # -3.5 sample peak keeps the inter-sample (true) peak at or under -3 dBFS.
    return x * (db_to_lin(min(peak_db, -3.5)) / (peak(x) + 1e-9))


# --- footsteps (heavy knight) -----------------------------------------------

def step_stone(rng):
    n = nn(0.26)
    x = np.zeros(n)
    add(x, thump(rng, rng.uniform(125, 150), rng.uniform(62, 72), 0.03, 0.05, 0.25), 0.0, 1.0)
    add(x, crack(rng, 0.04, 1600.0, 5200.0, 0.005), 0.0, 0.5)
    add(x, bpn(white(nn(0.12), rng), 600.0, 2400.0) * window(nn(0.12), 0.012, 0.04), 0.01, 0.12)
    add(x, armor(rng, 2, 0.05, 0.18), 0.02, 1.0)
    return x


def step_dirt(rng):
    n = nn(0.28)
    x = np.zeros(n)
    add(x, thump(rng, rng.uniform(90, 115), rng.uniform(55, 62), 0.035, 0.06, 0.25, 0.4), 0.0, 1.0)
    add(x, lp(grit(rng, 0.12, 14, 800.0, 3800.0, 0.012), 3500.0), 0.005, 0.38)
    add(x, armor(rng, 2, 0.05, 0.14), 0.02, 1.0)
    return x


def step_metal(rng):
    n = nn(0.36)
    x = np.zeros(n)
    add(x, thump(rng, rng.uniform(105, 125), rng.uniform(54, 60), 0.04, 0.1, 0.3, 1.0), 0.0, 1.0)
    f = rng.uniform(0.94, 1.08) * 190.0
    add(x, ring(f, [1.0, 2.17, 4.05, 6.6], [1.0, 0.7, 0.5, 0.3], [0.13, 0.09, 0.06, 0.04], 0.3), 0.0, 0.4)
    add(x, crack(rng, 0.05, 2000.0, 7000.0, 0.006), 0.0, 0.4)
    add(x, armor(rng, 3, 0.06, 0.24), 0.015, 1.0)
    return x


def step_wet(rng):
    n = nn(0.3)
    x = np.zeros(n)
    add(x, thump(rng, rng.uniform(110, 130), rng.uniform(58, 66), 0.03, 0.05, 0.25, 0.6), 0.0, 0.9)
    m = nn(0.14)
    u = np.linspace(0, 1, m)
    splash = tv_bandpass(white(m, rng), 3600.0 * (0.33 ** u), bw_oct=1.6) * window(m, 0.004, 0.05)
    add(x, pk(splash), 0.005, 0.7)
    add(x, crack(rng, 0.05, 2500.0, 8000.0, 0.01), 0.01, 0.2)
    return x


def step_sludge(rng):
    n = nn(0.36)
    x = np.zeros(n)
    add(x, lp(thump(rng, rng.uniform(85, 100), rng.uniform(52, 58), 0.04, 0.07, 0.3, 0.5), 900.0), 0.0, 0.9)
    m = nn(0.2)
    u = np.linspace(0, 1, m)
    squelch = tv_bandpass(white(m, rng), 520.0 * (0.5 ** u), bw_oct=1.2) * window(m, 0.01, 0.07)
    add(x, pk(squelch), 0.01, 0.7)
    for _ in range(3):
        f0 = rng.uniform(170, 260)
        add(x, bubble(rng, f0, f0 * rng.uniform(1.6, 2.4), 0.08), rng.uniform(0.04, 0.22), rng.uniform(0.3, 0.6))
    return x


# --- movement / combat ------------------------------------------------------

def land(rng):
    x = np.zeros(nn(0.3))
    add(x, thump(rng, 150.0, 62.0, 0.03, 0.07, 0.3), 0.0, 1.0)
    add(x, crack(rng, 0.05, 1200.0, 4500.0, 0.008), 0.0, 0.45)
    add(x, armor(rng, 3, 0.07, 0.25), 0.01, 1.0)
    return x


def land_heavy(rng):
    x = np.zeros(nn(0.8))
    add(x, thump(rng, 125.0, 52.0, 0.05, 0.2, 0.7, 1.2), 0.0, 1.0)
    add(x, bpn(white(nn(0.3), rng), 200.0, 2500.0) * window(nn(0.3), 0.004, 0.1), 0.0, 0.5)
    for t in (0.03, 0.08, 0.14, 0.22):
        add(x, armor(rng, 3, 0.05, 0.4), t, 1.0)
    for _ in range(4):
        f = rng.uniform(900.0, 2600.0)
        add(x, ring(f, [1.0, 2.2], [1.0, 0.4], [0.03, 0.015], 0.1), rng.uniform(0.06, 0.4), rng.uniform(0.1, 0.25))
    add(x, lpn(brown(nn(0.6), rng), 130.0) * exp_env(nn(0.6), 0.22), 0.0, 0.25)
    return x


def jump(rng):
    x = np.zeros(nn(0.24))
    add(x, bpn(white(nn(0.2), rng), 500.0, 2200.0) * window(nn(0.2), 0.03, 0.07), 0.0, 0.55)
    add(x, thump(rng, 110.0, 70.0, 0.02, 0.04, 0.2, 0.3), 0.0, 0.6)
    add(x, armor(rng, 2, 0.05, 0.16), 0.01, 1.0)
    return x


def dash(rng):
    x = np.zeros(nn(0.44))
    add(x, whoosh(rng, 0.4, 1400.0, 4200.0, 2000.0, 1.7, 0.3, 1.6), 0.0, 1.0)
    add(x, bpn(white(nn(0.3), rng), 350.0, 1500.0) * window(nn(0.3), 0.02, 0.09), 0.01, 0.35)
    return x


def swing(rng):
    n = nn(0.44)
    x = np.zeros(n)
    add(x, whoosh(rng, 0.44, 520.0, 2300.0, 900.0, 1.6, 0.45, 2.0), 0.0, 1.0)
    add(x, whoosh(rng, 0.44, 210.0, 430.0, 260.0, 1.4, 0.45, 2.0), 0.0, 0.5)
    add(x, _unit(resonator(white(n, rng), 3100.0, 8.0)) * window(n, 0.12, 0.1), 0.0, 0.04)
    return x


def swing_heavy(rng):
    n = nn(0.66)
    x = np.zeros(n)
    add(x, whoosh(rng, 0.66, 260.0, 1500.0, 420.0, 1.9, 0.55, 2.2), 0.0, 1.0)
    add(x, whoosh(rng, 0.66, 110.0, 260.0, 150.0, 1.5, 0.55, 2.0), 0.0, 0.7)
    add(x, thump(rng, 120.0, 60.0, 0.03, 0.09, 0.3, 0.5), 0.34, 0.45)
    add(x, _unit(resonator(white(n, rng), 2700.0, 7.0)) * window(n, 0.3, 0.12), 0.0, 0.05)
    return x


def boss_axe_swing(rng):
    n = nn(1.1)
    x = np.zeros(n)
    add(x, whoosh(rng, 1.1, 150.0, 950.0, 210.0, 2.0, 0.55, 2.4), 0.0, 1.0)
    add(x, whoosh(rng, 1.1, 70.0, 190.0, 90.0, 1.5, 0.55, 2.0), 0.0, 0.9)
    add(x, lpn(brown(n, rng), 140.0) * np.sin(np.linspace(0, np.pi, n)) ** 2, 0.0, 0.5)
    add(x, _unit(resonator(white(n, rng), 1900.0, 6.0)) * window(n, 0.5, 0.15), 0.0, 0.05)
    return x


def hit_metal(rng):
    x = np.zeros(nn(0.6))
    add(x, crack(rng, 0.03, 2500.0, 9000.0, 0.004), 0.0, 0.8)
    f = rng.uniform(0.92, 1.1) * 880.0
    add(x, ring(f, [1.0, 2.76, 5.4, 8.93], [1.0, 0.7, 0.45, 0.3], [0.22, 0.14, 0.08, 0.05], 0.55, 0.002), 0.0, 0.55)
    add(x, thump(rng, 260.0, 120.0, 0.02, 0.05, 0.25, 0.4), 0.0, 0.7)
    return x


def hit_bone(rng):
    x = np.zeros(nn(0.3))
    add(x, crack(rng, 0.05, 1800.0, 7000.0, 0.008), 0.0, 0.9)
    add(x, pk(sine_sweep(nn(0.12), 280.0 * rng.uniform(0.9, 1.1), 520.0, 0.012) * exp_env(nn(0.12), 0.035)), 0.0, 0.7)
    for t in (0.015, 0.03, 0.05, 0.075):
        add(x, crack(rng, 0.04, 1000.0, 5000.0, 0.012), t, rng.uniform(0.25, 0.5))
    add(x, thump(rng, 160.0, 130.0, 0.02, 0.025, 0.15, 0.2), 0.0, 0.5)
    return x


def hit_heavy(rng):
    x = np.zeros(nn(0.8))
    add(x, thump(rng, 175.0, 52.0, 0.05, 0.22, 0.7, 1.4), 0.0, 1.0)
    add(x, crack(rng, 0.08, 800.0, 6000.0, 0.012), 0.0, 0.8)
    add(x, ring(300.0 * rng.uniform(0.9, 1.1), [1.0, 2.41, 3.77], [0.5, 0.35, 0.2], [0.25, 0.15, 0.09], 0.4), 0.0, 0.6)
    add(x, lpn(white(nn(0.3), rng), 1500.0) * exp_env(nn(0.3), 0.12), 0.0, 0.25)
    return x


def shield_block(rng):
    x = np.zeros(nn(0.65))
    add(x, pk(sine_sweep(nn(0.3), 95.0, 190.0, 0.03) * exp_env(nn(0.3), 0.08)), 0.0, 0.9)
    add(x, ring(1100.0 * rng.uniform(0.92, 1.08), [1.0, 2.3, 4.1, 6.7], [0.7, 0.5, 0.3, 0.2], [0.15, 0.09, 0.05, 0.03], 0.5), 0.0, 0.7)
    add(x, crack(rng, 0.06, 2000.0, 6500.0, 0.02), 0.0, 0.35)
    add(x, crack(rng, 0.05, 300.0, 1200.0, 0.02), 0.0, 0.3)
    return x


def shield_break(rng):
    x = np.zeros(nn(1.2))
    add(x, crack(rng, 0.05, 1500.0, 8000.0, 0.006), 0.0, 0.9)
    add(x, thump(rng, 130.0, 62.0, 0.04, 0.12, 0.4, 1.0), 0.0, 0.8)
    for _ in range(11):
        f = rng.uniform(1500.0, 5500.0)
        tau = rng.uniform(0.05, 0.22)
        add(x, ring(f, [1.0, 2.4, 3.9], [1.0, 0.5, 0.3], [tau, tau * 0.6, tau * 0.35], 0.5), rng.uniform(0.02, 0.4), rng.uniform(0.15, 0.4))
    add(x, lpn(white(nn(0.7), rng), 900.0) * window(nn(0.7), 0.02, 0.2), 0.02, 0.4)
    return x


def enemy_die(rng):
    x = np.zeros(nn(1.0))
    n = nn(0.8)
    u = np.linspace(0, 1, n)
    defl = tv_bandpass(white(n, rng), 1800.0 * (0.17 ** u), bw_oct=1.5) * window(n, 0.02, 0.32)
    add(x, rn(defl), 0.0, 0.5)
    add(x, thump(rng, 120.0, 58.0, 0.04, 0.12, 0.4, 0.8), 0.05, 0.9)
    for _ in range(5):
        f = rng.uniform(700.0, 1500.0)
        add(x, ring(f, [1.0, 2.2], [1.0, 0.4], [0.02, 0.01], 0.06), rng.uniform(0.1, 0.55), rng.uniform(0.15, 0.3))
    add(x, lpn(white(nn(0.6), rng), 4000.0) * exp_env(nn(0.6), 0.28), 0.05, 0.12)
    return x


def death(rng):
    x = np.zeros(nn(2.0))
    add(x, thump(rng, 120.0, 52.0, 0.05, 0.22, 0.8, 1.2), 0.0, 1.0)
    add(x, thump(rng, 100.0, 50.0, 0.05, 0.2, 0.7, 1.0), 0.18, 0.7)
    for i in range(9):
        f = rng.uniform(300.0, 2200.0)
        tau = rng.uniform(0.06, 0.3)
        add(x, ring(f, [1.0, 2.31, 3.9], [1.0, 0.5, 0.3], [tau, tau * 0.6, tau * 0.35], 0.5), rng.uniform(0.0, 0.7) ** 1.2, rng.uniform(0.2, 0.5))
    n = nn(1.3)
    u = np.linspace(0, 1, n)
    steam = tv_bandpass(white(n, rng), 2500.0 * (0.25 ** u), bw_oct=1.6) * window(n, 0.2, 0.5)
    add(x, rn(steam), 0.3, 0.25)
    add(x, lpn(brown(nn(1.5), rng), 140.0) * exp_env(nn(1.5), 0.6), 0.0, 0.4)
    return mono_reverb(x, rng, 1.3, 0.22)


def toxin_warn(rng):
    x = np.zeros(nn(0.65))
    for i, a in enumerate((1.0, 0.75)):
        add(x, thump(rng, 100.0, 55.0, 0.03, 0.09, 0.25, 0.8), 0.22 * i, a)
    n = nn(0.55)
    t = tt(n)
    flutter = np.clip(np.sin(TAU * 16.0 * t), 0.0, 1.0) ** 2
    hiss = bpn(white(n, rng), 2500.0, 6500.0) * flutter * window(n, 0.03, 0.2)
    add(x, rn(hiss), 0.0, 0.35)
    for _ in range(4):
        f = rng.uniform(280, 420)
        add(x, bubble(rng, f, f * 2.6, 0.07), rng.uniform(0.0, 0.45), rng.uniform(0.25, 0.5))
    return x


def heal(rng):
    n = nn(1.2)
    x = np.zeros(n)
    for f, a, d in [(220.0, 1.0, 0.0), (329.6, 0.8, 0.04), (440.0, 0.7, 0.08), (554.4, 0.5, 0.12)]:
        k = partials(n, f, [1.0, 2.0, 3.0], [1.0, 0.25, 0.08], [0.55, 0.3, 0.15])
        add(x, k * attack_env(n, 0.16), d, a)
    x = lp(x, 2200.0)
    for _ in range(7):
        f = rng.uniform(1700.0, 3600.0)
        add(x, ring(f, [1.0, 2.0], [1.0, 0.3], [0.09, 0.05], 0.3), rng.uniform(0.1, 0.8), rng.uniform(0.04, 0.1))
    add(x, lpn(white(nn(1.0), rng), 2500.0) * np.sin(np.linspace(0, np.pi, nn(1.0))) ** 2, 0.0, 0.05)
    return x


def parry(rng):
    x = np.zeros(nn(0.95))
    add(x, crack(rng, 0.03, 3000.0, 10000.0, 0.004), 0.0, 0.8)
    f = 1650.0 * rng.uniform(0.97, 1.03)
    add(x, ring(f, [1.0, 2.76, 5.4, 8.9, 11.3], [1.0, 0.8, 0.5, 0.3, 0.2], [0.35, 0.22, 0.12, 0.06, 0.04], 0.9, 0.0022), 0.0, 0.7)
    add(x, ring(830.0, [1.0, 2.41, 3.8], [0.5, 0.35, 0.2], [0.3, 0.18, 0.1], 0.6, 0.0016), 0.0, 0.45)
    add(x, pk(sine_sweep(nn(0.3), 90.0, 210.0, 0.03) * exp_env(nn(0.3), 0.09)), 0.0, 0.85)
    add(x, _unit(resonator(white(nn(0.3), rng), 5200.0, 12.0)) * exp_env(nn(0.3), 0.06), 0.0, 0.2)
    return x


def hurt(rng):
    x = np.zeros(nn(0.6))
    add(x, thump(rng, 160.0, 70.0, 0.03, 0.08, 0.3, 1.0), 0.0, 1.0)
    for t, a in ((0.0, 0.5), (0.03, 0.35), (0.07, 0.25)):
        f = rng.uniform(600.0, 1800.0)
        add(x, ring(f, [1.0, 2.4, 3.8], [1.0, 0.5, 0.3], [0.1, 0.06, 0.04], 0.3), t, a)
    add(x, bpn(white(nn(0.12), rng), 300.0, 1800.0) * exp_env(nn(0.12), 0.03), 0.0, 0.45)
    add(x, crack(rng, 0.04, 1500.0, 5000.0, 0.006), 0.0, 0.4)
    return x


def spit(rng):
    x = np.zeros(nn(0.6))
    add(x, rn(bpn(white(nn(0.3), rng), 600.0, 2400.0) * window(nn(0.3), 0.01, 0.08)), 0.0, 0.55)
    add(x, pk(sine_sweep(nn(0.1), 380.0, 1300.0, 0.012) * exp_env(nn(0.1), 0.03)), 0.0, 0.5)
    add(x, rn(bpn(white(nn(0.3), rng), 1500.0, 6000.0) * window(nn(0.3), 0.004, 0.05)), 0.07, 0.35)
    for _ in range(3):
        f = rng.uniform(500, 900)
        add(x, bubble(rng, f, f * 1.8, 0.05), rng.uniform(0.1, 0.4), rng.uniform(0.1, 0.25))
    return x


def spit_charge(rng):
    n = nn(0.75)
    x = np.zeros(n)
    t = tt(n)
    u = np.linspace(0, 1, n)
    gurgle = tv_bandpass(white(n, rng), 350.0 * (3.1 ** u), bw_oct=1.3) * (0.55 + 0.45 * np.sin(TAU * 22.0 * t))
    gurgle *= (u ** 1.5) * (u < 0.94)
    add(x, rn(gurgle), 0.0, 0.7)
    for i in range(7):
        tb = 0.7 * (i / 7.0) ** 0.7
        f = 250.0 + 450.0 * (i / 7.0)
        add(x, bubble(rng, f, f * 2.0, 0.06), tb, 0.35)
    add(x, rn(bpn(white(n, rng), 2500.0, 6000.0)) * (u ** 2) * (u < 0.94), 0.0, 0.08)
    return x


def ghost_wail(rng):
    n = nn(1.9)
    u = np.linspace(0, 1, n)
    t = tt(n)
    base = np.where(u < 0.35, 520.0 + (880.0 - 520.0) * np.clip(u / 0.35, 0.0, 1.0) ** 0.8,
                    880.0 + (450.0 - 880.0) * np.clip((u - 0.35) / 0.65, 0.0, 1.0) ** 0.9)
    vib = 1.0 + (0.012 + 0.02 * u) * np.sin(TAU * 5.5 * t)
    f = base * vib
    x = np.sin(osc_phase(f)) + 0.45 * np.sin(osc_phase(f * 1.4983 * 1.004)) + 0.25 * np.sin(osc_phase(f * 2.0))
    breath = tv_bandpass(white(n, rng), base * 1.6, bw_oct=0.5)
    x = x + 0.35 * rn(breath)
    env = attack_env(n, 0.3) * np.where(u < 0.5, 1.0, np.cos(0.5 * np.pi * np.clip((u - 0.5) / 0.5, 0.0, 1.0)) ** 1.5)
    x = lp(x * env, 6000.0)
    return mono_reverb(x, rng, 2.2, 0.55, 2800.0)


def skull_flame(rng):
    n = nn(0.75)
    x = np.zeros(n)
    u = np.linspace(0, 1, n)
    f = np.where(u < 0.25, 300.0 * (8.3 ** (u / 0.25)), 2500.0 * (0.48 ** ((u - 0.25) / 0.75)))
    add(x, rn(tv_bandpass(white(n, rng), f, bw_oct=2.0) * window(n, 0.08, 0.25)), 0.0, 0.7)
    add(x, rn(lpn(white(n, rng), 250.0) * window(n, 0.05, 0.3)), 0.0, 0.45)
    for _ in range(13):
        add(x, crack(rng, 0.03, 2000.0, 8000.0, 0.004), rng.uniform(0.05, 0.6), rng.uniform(0.1, 0.3))
    add(x, rn(hpn(white(n, rng), 5000.0) * window(n, 0.1, 0.25)), 0.0, 0.07)
    return x


def hook_fire(rng):
    n = nn(0.42)
    x = np.zeros(n)
    add(x, crack(rng, 0.04, 3000.0, 9000.0, 0.012), 0.0, 0.6)
    t, gap = 0.01, 0.02
    for i in range(14):
        add(x, ring(rng.uniform(1700.0, 2500.0), [1.0, 1.9], [1.0, 0.5], [0.012, 0.007], 0.04), t, 0.8 * (0.9 ** i))
        t += gap * (0.92 ** i)
    add(x, whoosh(rng, 0.3, 800.0, 3200.0, 1500.0, 1.8, 0.35, 1.6), 0.0, 0.4)
    add(x, ring(520.0, [1.0, 2.0], [1.0, 0.3], [0.1, 0.05], 0.3), 0.0, 0.25)
    return x


def hook_hit(rng):
    x = np.zeros(nn(0.55))
    add(x, ring(1450.0 * rng.uniform(0.95, 1.05), [1.0, 2.2, 3.6, 5.8], [0.8, 0.5, 0.3, 0.2], [0.18, 0.1, 0.06, 0.03], 0.5, 0.002), 0.0, 0.7)
    add(x, thump(rng, 125.0, 75.0, 0.02, 0.05, 0.25, 0.6), 0.0, 0.8)
    add(x, crack(rng, 0.03, 2500.0, 8000.0, 0.003), 0.04, 0.5)
    return x


def plate_click(rng):
    x = np.zeros(nn(0.32))
    add(x, thump(rng, 110.0, 68.0, 0.025, 0.05, 0.25, 0.4), 0.0, 0.8)
    add(x, crack(rng, 0.04, 1500.0, 4500.0, 0.004), 0.0, 0.6)
    add(x, crack(rng, 0.03, 2500.0, 8000.0, 0.003), 0.06, 0.35)
    add(x, rn(bpn(white(nn(0.12), rng), 400.0, 1400.0) * window(nn(0.12), 0.01, 0.04)), 0.02, 0.18)
    return x


def rustgate_melt(rng):
    n = nn(2.1)
    x = np.zeros(n)
    t = tt(n)
    env = np.exp(-t / 1.1) * attack_env(n, 0.05)
    sizzle = hpn(white(n, rng), 3500.0) * (rng.random(n) > 0.55) * env
    add(x, rn(lp(sizzle, 9000.0)), 0.0, 0.3)
    bub = bpn(white(n, rng), 250.0, 1000.0) * np.clip(np.sin(TAU * 11.0 * t + 0.6 * np.sin(TAU * 1.3 * t)), 0.0, 1.0) ** 2 * env
    add(x, rn(bub), 0.0, 0.5)
    groan = np.sin(osc_phase(glide(n, 190.0, 72.0)))
    groan = saturate(groan * 1.5, 1.5) * np.exp(-t / 0.9) * attack_env(n, 0.1)
    add(x, lp(groan, 800.0), 0.0, 0.5)
    for _ in range(6):
        f = rng.uniform(500, 1200)
        add(x, bubble(rng, f * 0.8, f * 1.8, 0.09), rng.uniform(0.7, 1.9), rng.uniform(0.1, 0.25))
    return x


def nest_light(rng):
    n = nn(1.5)
    x = np.zeros(n)
    u = np.linspace(0, 1, n)
    f = 200.0 * (9.0 ** np.clip(u / 0.2, 0, 1)) * np.where(u > 0.2, 0.55 ** ((u - 0.2) / 0.8), 1.0)
    add(x, rn(tv_bandpass(white(n, rng), f, bw_oct=2.0) * window(n, 0.1, 0.4)), 0.0, 0.7)
    add(x, rn(lpn(white(n, rng), 300.0) * window(n, 0.12, 0.6)), 0.0, 0.5)
    for _ in range(32):
        tb = rng.uniform(0.05, 1.1) ** 1.2
        add(x, crack(rng, 0.03, 2200.0, 8000.0, 0.004), tb, rng.uniform(0.08, 0.28) * (1.0 - 0.6 * tb / 1.2))
    add(x, np.sin(TAU * 220.0 * tt(nn(1.2))) * window(nn(1.2), 0.15, 0.5), 0.0, 0.07)
    return x


def nest_rest(rng):
    n = nn(2.2)
    x = np.zeros(n)
    for f, a in [(146.8, 1.0), (220.0, 0.8), (293.7, 0.55)]:
        k = partials(n, f, [1.0, 2.0, 3.0], [1.0, 0.3, 0.1], [0.9, 0.5, 0.25]) * attack_env(n, 0.5)
        add(x, k, 0.0, a)
    x = lp(x, 1200.0)
    add(x, rn(lpn(white(nn(1.8), rng), 1200.0) * window(nn(1.8), 0.6, 0.6)), 0.0, 0.18)
    for _ in range(14):
        tb = rng.uniform(0.1, 1.9)
        add(x, crack(rng, 0.03, 2200.0, 8000.0, 0.004), tb, rng.uniform(0.04, 0.12) * (1.0 - tb / 2.4))
    return x


def core_get(rng):
    n = nn(2.0)
    x = np.zeros(n)
    add(x, ring(440.0, [1.0, 1.5, 2.0, 2.76, 4.1], [1.0, 0.6, 0.5, 0.3, 0.2], [1.2, 0.9, 0.7, 0.4, 0.25], 1.9, 0.0025), 0.02, 0.8)
    sweep = np.sin(osc_phase(glide(nn(0.45), 220.0, 880.0, curve=1.6))) * np.sin(np.linspace(0, np.pi, nn(0.45))) ** 1.5
    add(x, sweep, 0.0, 0.35)
    add(x, rn(tv_bandpass(white(nn(0.7), rng), 250.0 * (4.0 ** np.linspace(0, 1, nn(0.7))), 1.8) * window(nn(0.7), 0.05, 0.2)), 0.05, 0.4)
    for _ in range(9):
        f = rng.uniform(1800.0, 4200.0)
        add(x, ring(f, [1.0, 2.0], [1.0, 0.3], [0.12, 0.06], 0.4), rng.uniform(0.1, 1.0), rng.uniform(0.05, 0.12))
    return mono_reverb(x, rng, 1.4, 0.3)


def door_open(rng):
    n = nn(1.7)
    x = np.zeros(n)
    add(x, rn(lpn(brown(n, rng), 160.0) * attack_env(n, 0.15) * np.where(tt(n) < 1.2, 1.0, np.exp(-(tt(n) - 1.2) / 0.15))), 0.0, 0.5)
    for name, gain, up, down in (("doorOpen_2.ogg", 0.8, 5, 6), ("creak3.ogg", 0.7, 3, 4)):
        path = KENNEY / name
        if path.exists():
            src = read_audio(path, SR, 1)[0]
            src = signal.resample_poly(src, up, down)
            src = lp(src, 4500.0, 2)
            add(x, pk(src), 0.0, gain)
    add(x, thump(rng, 120.0, 60.0, 0.03, 0.07, 0.3, 0.6), 0.0, 0.5)
    add(x, rn(bpn(white(nn(0.5), rng), 700.0, 2500.0) * window(nn(0.5), 0.1, 0.2)), 0.4, 0.08)
    return x


def bell_toll(rng):
    x = bell_note(164.8, 1.0, rng, length=6.0, decay=1.1)
    return mono_reverb(x, rng, 2.4, 0.25, 2800.0)


def forge_pulse(rng):
    n = nn(0.95)
    x = np.zeros(n)
    add(x, thump(rng, 100.0, 52.0, 0.04, 0.18, 0.6, 1.0), 0.0, 1.0)
    add(x, rn(lpn(brown(n, rng), 300.0) * window(n, 0.1, 0.35)), 0.0, 0.45)
    add(x, ring(170.0, [1.0, 2.4], [1.0, 0.4], [0.3, 0.15], 0.6), 0.0, 0.1)
    add(x, rn(bpn(white(n, rng), 2500.0, 5000.0) * window(n, 0.12, 0.3)), 0.0, 0.05)
    return x


def ui_pause(rng):
    x = np.zeros(nn(0.36))
    add(x, pk(sine_sweep(nn(0.3), 90.0, 190.0, 0.03) * exp_env(nn(0.3), 0.07)), 0.0, 1.0)
    add(x, rn(lpn(white(nn(0.12), rng), 1800.0) * exp_env(nn(0.12), 0.05)), 0.0, 0.2)
    add(x, crack(rng, 0.04, 800.0, 2500.0, 0.01), 0.0, 0.3)
    return x


def ui_tick(rng):
    x = np.zeros(nn(0.08))
    add(x, crack(rng, 0.03, 1800.0, 5000.0, 0.004), 0.0, 1.0)
    add(x, np.sin(TAU * 900.0 * tt(nn(0.05))) * exp_env(nn(0.05), 0.012), 0.0, 0.35)
    return x


def hint_show(rng):
    x = np.zeros(nn(0.55))
    add(x, ring(880.0, [1.0, 2.0, 3.0], [1.0, 0.3, 0.1], [0.22, 0.12, 0.06], 0.5) * attack_env(nn(0.5), 0.004), 0.0, 0.8)
    add(x, ring(1318.5, [1.0, 2.0], [1.0, 0.25], [0.25, 0.1], 0.5) * attack_env(nn(0.5), 0.004), 0.09, 0.6)
    return lp(x, 5000.0)


def drip(rng):
    n = nn(0.32)
    t = tt(n)
    f = rng.uniform(800.0, 1300.0)
    ft = f * (1.0 + 2.2 * (1.0 - np.exp(-t / 0.012)))
    x = np.sin(osc_phase(ft)) * exp_env(n, 0.03) * attack_env(n, 0.001)
    return mono_reverb(x, rng, 0.9, 0.35, 3000.0)


def gear_creak(rng):
    n = nn(1.2)
    t = tt(n)
    u = np.linspace(0, 1, n)
    f = 900.0 + 500.0 * np.sin(TAU * 1.7 * t) * 0.5 + 400.0 * u
    x = rn(tv_bandpass(white(n, rng), f, bw_oct=0.3))
    x *= 0.6 + 0.4 * np.sin(TAU * 13.0 * t + 2.0 * np.sin(TAU * 2.3 * t))
    x *= np.sin(np.pi * u) ** 1.5
    return x


def boss_axe_slam(rng):
    n = nn(1.8)
    x = np.zeros(n)
    add(x, thump(rng, 130.0, 50.0, 0.06, 0.4, 1.4, 1.5), 0.0, 1.0)
    add(x, crack(rng, 0.1, 600.0, 7500.0, 0.015), 0.0, 0.9)
    for i in range(13):
        tb = rng.uniform(0.05, 0.8) ** 1.1
        add(x, bpn(white(nn(0.12), rng), rng.uniform(400, 1500), rng.uniform(1800, 3500)) * exp_env(nn(0.12), 0.02), tb, rng.uniform(0.1, 0.35) * (1.0 - tb))
    add(x, ring(210.0, [1.0, 2.4, 3.9, 6.1], [0.5, 0.4, 0.3, 0.2], [0.6, 0.35, 0.2, 0.1], 1.2, 0.002), 0.0, 0.45)
    add(x, rn(lpn(brown(nn(1.2), rng), 110.0) * exp_env(nn(1.2), 0.5)), 0.0, 0.5)
    return mono_reverb(x, rng, 1.3, 0.25)


def boss_roar(rng):
    n = nn(2.1)
    t = tt(n)
    u = np.linspace(0, 1, n)
    base = np.where(u < 0.3, 80.0 + 50.0 * (u / 0.3), 130.0 - 50.0 * np.clip((u - 0.3) / 0.7, 0.0, 1.0) ** 0.8)
    f = base * (1.0 + 0.03 * np.sin(TAU * 6.0 * t))
    src = saw_from_phase(osc_phase(f)) * (0.6 + 0.4 * np.sin(TAU * 55.0 * t))
    src = src + 0.3 * white(n, rng)
    f1 = 750.0 - 300.0 * u
    f2 = 1150.0 - 350.0 * u
    voiced = tv_bandpass(src, f1, 0.6) + 0.6 * tv_bandpass(src, f2, 0.6) + 0.3 * bp(src, 2300.0, 3000.0)
    env = attack_env(n, 0.25) * np.where(u < 0.7, 1.0, np.cos(0.5 * np.pi * np.clip((u - 0.7) / 0.3, 0.0, 1.0)) ** 1.5)
    x = saturate(rn(voiced) * env * 0.8, 2.5)
    x = lp(x, 5000.0)
    return mono_reverb(x, rng, 1.5, 0.2)


def horse_charge(rng):
    n = nn(1.7)
    x = np.zeros(n)
    cycle = 0.40
    for c in range(4):
        for k, off in enumerate((0.0, 0.1, 0.2)):
            tb = c * cycle + off
            amp = 0.35 + 0.65 * (tb / 1.6)
            add(x, thump(rng, 90.0, 56.0, 0.02, 0.06, 0.2, 0.8), tb, amp)
            add(x, crack(rng, 0.03, 1200.0, 3500.0, 0.008), tb, 0.45 * amp)
            add(x, armor(rng, 2, 0.04, 0.35), tb + 0.01, amp)
    add(x, rn(bpn(white(nn(0.3), rng), 300.0, 1200.0) * window(nn(0.3), 0.04, 0.1)), 0.0, 0.18)
    add(x, rn(hpn(white(nn(1.5), rng), 2500.0) * np.sin(np.linspace(0, np.pi, nn(1.5))) ** 2) * 0.1, 0.0, 1.0)
    return x


def gear_clank(rng):
    return pk(ring(1200.0 * rng.uniform(0.85, 1.2), [1.0, 1.7, 2.9, 4.4], [1.0, 0.7, 0.4, 0.25], [0.09, 0.06, 0.04, 0.025], 0.4))


# --- registry ---------------------------------------------------------------

# name -> (function, peak dBFS, variants, extra finish kwargs)
# Dedicated hazard cues: pressure release, stone failure, gust and bronze motion.
def hazard_steam(rng):
    dur = 1.05
    t = tt(nn(dur))
    x = bpn(white(len(t), rng), 900, 9500) * np.sin(np.pi * t / dur) ** 0.45
    x *= 0.7 + 0.3 * np.sin(TAU * 23 * t)
    add(x, thump(rng, 170, 70, decay=0.12), gain=0.25)
    return x


def hazard_flame(rng):
    return roar(1.2, rng, mid_gain=0.8, hiss_gain=0.18, crackle_rate=34, crackle_gain=0.7).mean(axis=0) * window(nn(1.2), 0.025, 0.5)


def hazard_slag(rng):
    x = np.zeros(nn(1.25))
    add(x, thump(rng, 130, 45, decay=0.28), gain=1.1)
    add(x, whoosh(rng, 0.8, 250, 1200, 400), t=0.08, gain=0.6)
    add(x, grit(rng, 0.9, 25, 500, 4200, 0.035), t=0.15, gain=0.7)
    return x


def hazard_bell(rng):
    x = ring(118, [1, 2.71, 4.05, 5.78], [1, 0.7, 0.4, 0.15], [1.1, 0.8, 0.6, 0.3], 2.0, 0.008)
    add(x, thump(rng, 180, 48, decay=0.2), gain=0.8)
    add(x, crack(rng, 0.12, 1200, 5600), gain=0.4)
    return x


def hazard_collapse(rng):
    x = np.zeros(nn(1.0))
    add(x, thump(rng, 105, 42, decay=0.2), gain=0.9)
    add(x, grit(rng, 0.85, 38, 280, 3600, 0.04), t=0.06, gain=0.8)
    return x


def hazard_pendulum(rng):
    x = whoosh(rng, 0.7, 200, 1800, 220, peak_at=0.52)
    add(x, ring(270, [1, 1.73, 3.41], [1, 0.35, 0.2], [0.25, 0.16, 0.1], 0.5), t=0.12, gain=0.25)
    return x


def hazard_wind(rng):
    return wind(1.5, rng, [(160, 720), (800, 2200)], gusts=1, widths=(0.5, 0.7), depth=0.8).mean(axis=0) * np.sin(np.pi * tt(nn(1.5)) / 1.5) ** 0.5


def hazard_pressure_warn(rng):
    return bpn(white(nn(0.5), rng), 1600, 5400) * window(nn(0.5), 0.035, 0.16)


def hazard_metal_warn(rng):
    x = ring(395, [1, 1.46, 2.8], [1, 0.5, 0.2], [0.22, 0.18, 0.1], 0.65, 0.007)
    add(x, grit(rng, 0.45, 7, 900, 4300), gain=0.3)
    return x


SOUNDS = {
    "step_stone": (step_stone, -6.0, 3, {"hp_hz": 50.0}),
    "step_dirt": (step_dirt, -8.0, 3, {"hp_hz": 45.0}),
    "step_metal": (step_metal, -5.0, 3, {"hp_hz": 45.0}),
    "step_wet": (step_wet, -6.0, 3, {"hp_hz": 45.0}),
    "step_sludge": (step_sludge, -7.0, 3, {"hp_hz": 45.0}),
    "land": (land, -5.0, 2, {"hp_hz": 45.0}),
    "land_heavy": (land_heavy, -3.0, 1, {"hp_hz": 40.0}),
    "jump": (jump, -9.0, 1, {}),
    "dash": (dash, -9.0, 1, {}),
    "swing": (swing, -4.0, 2, {}),
    "swing_heavy": (swing_heavy, -3.0, 2, {"hp_hz": 40.0}),
    "boss_axe_swing": (boss_axe_swing, -3.0, 1, {"hp_hz": 40.0}),
    "boss_axe_slam": (boss_axe_slam, -3.0, 1, {"hp_hz": 40.0, "fade": 0.05}),
    "boss_roar": (boss_roar, -3.0, 1, {"hp_hz": 45.0, "fade": 0.1}),
    "horse_charge": (horse_charge, -3.0, 1, {"hp_hz": 45.0, "fade": 0.06}),
    "hit_metal": (hit_metal, -3.0, 2, {}),
    "hit_bone": (hit_bone, -3.0, 2, {}),
    "hit_heavy": (hit_heavy, -3.0, 2, {"hp_hz": 40.0}),
    "shield_block": (shield_block, -3.0, 2, {}),
    "shield_break": (shield_break, -3.0, 1, {"fade": 0.06}),
    "parry": (parry, -3.0, 2, {"fade": 0.05}),
    "hurt": (hurt, -3.0, 1, {}),
    "enemy_die": (enemy_die, -3.0, 1, {"fade": 0.05}),
    "death": (death, -3.0, 1, {"hp_hz": 40.0, "fade": 0.15}),
    "spit": (spit, -8.0, 1, {}),
    "spit_charge": (spit_charge, -7.0, 1, {}),
    "ghost_wail": (ghost_wail, -6.0, 1, {"fade": 0.15}),
    "skull_flame": (skull_flame, -6.0, 1, {"fade": 0.05}),
    "toxin_warn": (toxin_warn, -6.0, 1, {"hp_hz": 45.0}),
    "heal": (heal, -6.0, 1, {"fade": 0.08}),
    "hook_fire": (hook_fire, -3.0, 1, {}),
    "hook_hit": (hook_hit, -3.0, 1, {}),
    "plate_click": (plate_click, -6.0, 1, {}),
    "rustgate_melt": (rustgate_melt, -6.0, 1, {"fade": 0.15}),
    "nest_light": (nest_light, -4.0, 1, {"fade": 0.1}),
    "nest_rest": (nest_rest, -6.0, 1, {"fade": 0.2}),
    "core_get": (core_get, -3.0, 1, {"fade": 0.2}),
    "door_open": (door_open, -3.0, 1, {"hp_hz": 40.0, "fade": 0.1}),
    "bell_toll": (bell_toll, -3.0, 1, {"hp_hz": 60.0, "fade": 0.4}),
    "forge_pulse": (forge_pulse, -4.0, 1, {"hp_hz": 40.0, "fade": 0.1}),
    "ui_pause": (ui_pause, -8.0, 1, {"hp_hz": 60.0}),
    "ui_tick": (ui_tick, -14.0, 1, {"hp_hz": 200.0}),
    "hint_show": (hint_show, -10.0, 1, {"fade": 0.1}),
    "drip": (drip, -12.0, 3, {"hp_hz": 200.0, "fade": 0.1}),
    "gear_creak": (gear_creak, -14.0, 2, {"hp_hz": 200.0, "fade": 0.1}),
}


SOUNDS.update({
    "hazard_steam": (hazard_steam, -8.0, 1, {}),
    "hazard_flame": (hazard_flame, -7.0, 1, {}),
    "hazard_slag": (hazard_slag, -6.0, 1, {}),
    "hazard_bell": (hazard_bell, -6.0, 1, {}),
    "hazard_shock": (forge_pulse, -8.0, 1, {}),
    "hazard_collapse": (hazard_collapse, -7.0, 1, {}),
    "hazard_pendulum": (hazard_pendulum, -10.0, 1, {}),
    "hazard_wind": (hazard_wind, -13.0, 1, {}),
    **{f"hazard_{kind}_warn": (hazard_pressure_warn if kind in ("steam", "flame", "slag") else hazard_metal_warn,
                                  -13.0, 1, {}) for kind in ("steam", "flame", "slag", "bell", "shock", "collapse")},
})


def variant_name(name: str, i: int, count: int) -> str:
    if count == 1:
        return name
    return f"{name}_{'abcdefgh'[i]}"


def build_sounds(only: str) -> None:
    total = 0
    for name, (fn, peak_db, count, kw) in SOUNDS.items():
        if only and only not in name:
            continue
        for i in range(count):
            out = variant_name(name, i, count)
            x = fn(rng_for(f"sfx:{out}"))
            x = finish(np.asarray(x, dtype=np.float64), peak_db, **kw)
            path = SFX / f"{out}.wav"
            write_wav(path, x)
            total += path.stat().st_size
            print(f"{out:<22} {len(x) / SR:5.2f}s  peak {20 * np.log10(peak(x)):6.1f} dBFS  {path.stat().st_size // 1024:>4} KB")
    print(f"one-shots total {total / 1024 / 1024:.2f} MB")


# --- ambience beds ----------------------------------------------------------

BED_LOOP = 24.0


def bed_wind(rng):
    x = wind(BED_LOOP, rng, [(220.0, 700.0), (600.0, 1500.0)], gusts=5, widths=(3.0, 6.0), depth=0.8,
             whistles=[(700.0, 28.0), (1100.0, 34.0)], whistle_gain=0.14)
    return x, -25.0, 6500.0


def bed_hall(rng):
    n = int(BED_LOOP * SR)
    x = drone(BED_LOOP, [38, 45], rng, voices=3, cents=8.0, partial_count=8, lfo_depth=0.6)
    air = np.stack([bpn(white(n, rng), 400.0, 3000.0, 2, circular=True) for _ in range(2)])
    mix_in(x, air, -16.0)
    from gen_audio_dsp import reverb as rv
    x = rv(x, reverb_ir(6.0, rng, damping=2200.0), 0.5, circular=True)
    return x, -29.0, 5000.0


def bed_forge(rng):
    return roar(BED_LOOP, rng, mid_gain=0.7, hiss_gain=0.05, crackle_rate=20.0, crackle_gain=0.55), -24.0, 7000.0


def bed_workshop(rng):
    n = int(BED_LOOP * SR)
    t = tt(n)
    x = hum(BED_LOOP, 100.0, rng, 1.0)
    fan = np.stack([bpn(white(n, rng), 600.0, 1800.0, 2, circular=True) for _ in range(2)])
    fan *= 0.65 + 0.35 * np.sin(TAU * 672 * t / BED_LOOP)
    mix_in(x, fan, -9.0)
    rumble = np.stack([lpn(brown(n, rng), 110.0, 2, circular=True) for _ in range(2)])
    mix_in(x, rumble, -6.0)
    return x, -27.0, 5500.0


def bed_core(rng):
    x = drone(BED_LOOP, [37, 38, 44], rng, voices=3, cents=12.0, partial_count=8, lfo_depth=0.9, tilt=1.1)
    mix_in(x, roar(BED_LOOP, rng, mid_gain=0.4, hiss_gain=0.03, crackle_rate=8.0, crackle_gain=0.3), -8.0)
    return x, -26.0, 5500.0


def bed_title(rng):
    # Quiet furnace pressure under a cavernous iron hall, with no rhythmic beat.
    x = drone(BED_LOOP, [36, 54], rng, voices=3, cents=5.0, partial_count=5, lfo_depth=0.35)
    mix_in(x, roar(BED_LOOP, rng, mid_gain=0.45, hiss_gain=0.035, crackle_rate=4.0, crackle_gain=0.14), -13.0)
    return x, -30.0, 4200.0


BEDS = {"bed_title": bed_title, "bed_wind": bed_wind, "bed_hall": bed_hall, "bed_forge": bed_forge, "bed_workshop": bed_workshop,
        "bed_core": bed_core}


def build_beds(only: str) -> None:
    for name, fn in BEDS.items():
        if only and only not in name:
            continue
        x, lufs, lp_hz = fn(rng_for("bed:" + name))
        x = finish_loop(x, lufs, lp_hz=lp_hz, hp_hz=45.0)
        path = AMB / f"{name}.ogg"
        encode_ogg(x, path, 2.0)
        m = measure(x)
        print(f"{name:<14} {x.shape[-1] / SR:5.1f}s  {m['lufs']:6.1f} LUFS  peak {m['true_peak']:6.1f}  {path.stat().st_size // 1024:>4} KB")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--no-beds", action="store_true")
    ap.add_argument("--no-sounds", action="store_true")
    args = ap.parse_args()
    t0 = time.time()
    if not args.no_sounds:
        build_sounds(args.only)
    if not args.no_beds:
        build_beds(args.only)
    print(f"done in {time.time() - t0:.0f}s")


if __name__ == "__main__":
    main()
