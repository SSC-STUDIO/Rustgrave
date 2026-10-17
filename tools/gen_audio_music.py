#!/usr/bin/env python3
"""Procedural soundtrack for Rustgrave -> assets/audio/music/*.ogg (project-original, CC0).

Every theme is three seamless stems that Music (scripts/autoload/music.gd) layers:
  <theme>_bed.ogg    40 s   drone + pad + weather texture   (always on)
  <theme>_keys.ogg   44-60 s sparse piano / bells, different length so bed and keys
                            drift against each other (the loop never repeats as a whole)
  <theme>_pulse.ogg  40 s   anvils / distorted kicks / chainsaw rasp ("danger" layer)
plus boss_<name>_bed / _hi, ending_bed / _keys and nine one-shot stingers.

Mood brief: docs/audio-mood.md (ambient industrial drones + lonely echoing piano;
combat = clashing anvils and broken chainsaws, low-end thud, no clean 808).
Loop rule (see gen_audio_dsp.py): integer cycles per loop for every oscillator,
circular filters, wrapped events, circular FFT reverb -> mathematically seamless.

usage: python tools/gen_audio_music.py [--only substring] [--jobs N] [--quality Q]
"""
from __future__ import annotations

import argparse
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_audio_dsp import (SR, ASSETS, rng_for, midi_hz, tt, snap, peak, to_stereo, place, lp, hp, bp,
                           resonator, tv_bandpass, saturate, white, pink, brown, exp_env, attack_env,
                           ad_env, sine_sweep, glide, osc_phase, saw_from_phase, partials, reverb_ir,
                           reverb, normalize_lufs, sub_cut, encode_ogg, fade_edges, measure, db_to_lin)

OUT = ASSETS / "audio" / "music"
LOOP = 40.0
N = int(round(LOOP * SR))
TAU = 2.0 * np.pi

AEOLIAN = [0, 2, 3, 5, 7, 8, 10]
PHRYGIAN = [0, 1, 3, 5, 7, 8, 10]
DORIAN = [0, 2, 3, 5, 7, 9, 10]
LOCRIAN = [0, 1, 3, 5, 6, 8, 10]
MINOR_PENT = [0, 3, 5, 7, 10]

# Integrated-loudness targets (LUFS, ffmpeg ebur128) per stem kind.
LUFS = {"bed": -22.0, "keys": -26.0, "pulse": -21.0, "boss_bed": -19.5, "boss_hi": -23.0,
        "title_keys": -23.5, "stinger": -17.0}


# --- instruments ------------------------------------------------------------

def piano_note(m: float, vel: float, rng: np.random.Generator, bright: float = 0.5, inharm: float = 0.00035,
               decay: float = 1.0, hammer: float = 0.3, max_len: float = 9.0) -> np.ndarray:
    """Additive felt/upright piano: inharmonic partials, two detuned strings, hammer thump."""
    f0 = midi_hz(m)
    tau0 = decay * 6.5 * (110.0 / f0) ** 0.55
    n = int(min(max_len, 6.9 * tau0) * SR)
    t = tt(n)
    out = np.zeros(n)
    spec_w = 2.0 + 14.0 * bright * vel
    for k in range(1, int(min(28, 9000.0 / f0)) + 1):
        fk = f0 * k * np.sqrt(1.0 + inharm * k * k)
        amp = (k ** -0.85) * np.exp(-(((k - 1) / spec_w) ** 1.4))
        if amp < 0.004:
            continue
        tau = tau0 / (1.0 + 0.5 * (k - 1))
        ph = rng.uniform(0, TAU)
        s = np.sin(TAU * fk * t + ph) + 0.7 * np.sin(TAU * fk * (1.0 + 0.0006 * rng.uniform(0.6, 1.4)) * t + 1.3 * ph)
        out += amp * s * np.exp(-t / tau)
    thump = lp(white(n, rng) * np.exp(-t / 0.010), 900.0 + 1500.0 * vel) * hammer
    out += thump * (0.5 if m > 60 else 1.0)
    out *= attack_env(n, 0.003)
    out = lp(out, 2800.0 + 7000.0 * bright * vel)
    return out * (vel ** 1.2) / (peak(out) + 1e-9)


def bell_note(f: float, vel: float, rng: np.random.Generator, length: float = 8.0, decay: float = 1.0) -> np.ndarray:
    """Church-bell partial set: hum, prime, minor tierce, quint, nominal ... with beating pairs."""
    n = int(length * SR)
    ratios = [0.5, 1.0, 1.19, 1.5, 2.0, 2.51, 3.01, 4.07, 5.33]
    amps = [0.65, 1.0, 0.72, 0.5, 0.58, 0.32, 0.28, 0.17, 0.1]
    taus = np.array([9.0, 6.5, 4.8, 3.9, 3.3, 2.1, 1.6, 1.0, 0.6]) * decay
    x = partials(n, f, ratios, amps, taus, detune=0.0028)
    t = tt(n)
    x += 0.5 * lp(white(n, rng) * np.exp(-t / 0.004), 5000.0)
    x *= attack_env(n, 0.0015)
    return x * vel / (peak(x) + 1e-9)


def metal_note(m: float, vel: float, rng: np.random.Generator) -> np.ndarray:
    """Struck-metal 'piano' (workshop / slag): strongly inharmonic, short ring."""
    return piano_note(m, vel, rng, bright=0.8, inharm=0.0065, decay=0.35, hammer=0.55, max_len=3.5)


def instrument(kind: str, m: float, vel: float, rng: np.random.Generator) -> np.ndarray:
    if kind == "felt":
        return piano_note(m, vel * 0.9, rng, bright=0.18, hammer=0.12)
    if kind == "honky":
        return piano_note(m, vel, rng, bright=0.62, inharm=0.0014, hammer=0.35)
    if kind == "metal":
        return metal_note(m, vel, rng)
    if kind == "bell":
        return bell_note(midi_hz(m), vel, rng)
    if kind == "glass":
        return piano_note(m, vel, rng, bright=0.95, inharm=0.0003, decay=0.7, hammer=0.05, max_len=6.0)
    return piano_note(m, vel, rng)


# --- percussion -------------------------------------------------------------

def kick(rng, f_hi=150.0, f_lo=47.0, tau_p=0.045, decay=0.32, drive=2.2, click=0.4, length=0.9) -> np.ndarray:
    n = int(length * SR)
    t = tt(n)
    body = sine_sweep(n, f_lo, f_hi, tau_p) * attack_env(n, 0.001) * np.exp(-t / decay)
    body += click * lp(white(n, rng), 3500.0) * np.exp(-t / 0.003)
    x = lp(saturate(body * 1.2, drive), 6500.0)
    return x / (peak(x) + 1e-9)


def anvil(rng, f=430.0, decay=0.55, length=1.5, bright=1.0) -> np.ndarray:
    n = int(length * SR)
    t = tt(n)
    f = f * rng.uniform(0.93, 1.07)
    ratios = [1.0, 2.41, 3.77, 5.21, 7.13, 9.6]
    amps = [1.0, 0.8, 0.6, 0.45, 0.3, 0.2]
    amps = [a * (bright ** i) for i, a in enumerate(amps)]
    taus = decay * np.array([1.0, 0.7, 0.45, 0.3, 0.18, 0.1])
    ring = partials(n, f, ratios, amps, taus, detune=0.0016)
    strike = hp(white(n, rng) * np.exp(-t / 0.004), 1800.0) * 0.9
    strike += sine_sweep(n, 70.0, 190.0, 0.02) * np.exp(-t / 0.05) * 0.8
    x = 0.7 * ring + strike
    return x / (peak(x) + 1e-9)


def tom(rng, f=95.0, decay=0.28, length=0.8) -> np.ndarray:
    n = int(length * SR)
    t = tt(n)
    x = sine_sweep(n, f, f * 1.7, 0.03) * np.exp(-t / decay) * attack_env(n, 0.001)
    x += 0.25 * lp(white(n, rng), 1800.0) * np.exp(-t / 0.012)
    x = saturate(x, 1.4)
    return x / (peak(x) + 1e-9)


def snare(rng, body=185.0, length=0.45) -> np.ndarray:
    n = int(length * SR)
    t = tt(n)
    x = bp(white(n, rng), 1100.0, 5200.0) * np.exp(-t / 0.11) * 0.9
    x += sine_sweep(n, body, body * 1.4, 0.015) * np.exp(-t / 0.05) * 0.6
    x = saturate(x, 1.6)
    return x / (peak(x) + 1e-9)


def scrape(rng, dur=0.55, f0=700.0, f1=2300.0) -> np.ndarray:
    n = int(dur * SR)
    t = tt(n)
    x = tv_bandpass(white(n, rng), glide(n, f0, f1), bw_oct=0.7)
    chop = 0.6 + 0.4 * np.sin(TAU * rng.uniform(21, 38) * t + rng.uniform(0, TAU))
    x *= chop * attack_env(n, 0.06) * np.exp(-t / 0.28)
    return x / (peak(x) + 1e-9)


def rasp(rng, f=88.0, dur=0.5, chop_hz=34.0) -> np.ndarray:
    """Broken chainsaw: dying saw motor, hard chop, random dropouts, distorted."""
    n = int(dur * SR)
    t = tt(n)
    saw = saw_from_phase(osc_phase(glide(n, f * 1.12, f * 0.74)))
    chop = lp(np.sign(np.sin(TAU * chop_hz * t)), 400.0) * 0.5 + 0.55
    x = (saw + 0.4 * white(n, rng)) * chop
    x = saturate(bp(x, 450.0, 3200.0) * 2.5, 3.0)
    gate = np.ones(n)
    for _ in range(3):
        c = int(rng.uniform(0.2, 0.9) * n)
        w = int(rng.uniform(0.012, 0.035) * SR)
        gate[c:c + w] = 0.0
    x *= gate * attack_env(n, 0.012) * np.exp(-t / 0.3)
    return x / (peak(x) + 1e-9)


def chug(rng, midi=28, dur=0.24) -> np.ndarray:
    n = int(dur * SR)
    t = tt(n)
    f = midi_hz(midi)
    x = saw_from_phase(osc_phase(np.full(n, f))) + 0.5 * saw_from_phase(osc_phase(np.full(n, f * 1.0035)))
    x = saturate(lp(x, 420.0, 2) * 2.2, 3.0) * attack_env(n, 0.004) * np.exp(-t / 0.095)
    x = hp(x, 40.0, 2)
    return x / (peak(x) + 1e-9)


def tick(rng, f=2600.0) -> np.ndarray:
    n = int(0.09 * SR)
    t = tt(n)
    x = bp(white(n, rng), f * 0.7, f * 1.4) * np.exp(-t / 0.006)
    x += 0.4 * np.sin(TAU * 900.0 * t) * np.exp(-t / 0.02)
    return x / (peak(x) + 1e-9)


def clank(rng, f=1200.0) -> np.ndarray:
    n = int(0.5 * SR)
    t = tt(n)
    x = partials(n, f * rng.uniform(0.85, 1.2), [1.0, 1.7, 2.9, 4.4], [1.0, 0.7, 0.4, 0.25], [0.09, 0.06, 0.04, 0.025])
    x += hp(white(n, rng) * np.exp(-t / 0.003), 2500.0)
    return x / (peak(x) + 1e-9)


def toll(rng, f=98.0) -> np.ndarray:
    return bell_note(f, 1.0, rng, length=7.0, decay=1.15)


VOICES = {"kick": kick, "anvil": anvil, "tom": tom, "snare": snare, "scrape": scrape, "rasp": rasp,
          "chug": chug, "tick": tick, "clank": clank, "toll": toll}


# --- loop textures (all circular) -------------------------------------------

def stereo_noise(n: int, rng: np.random.Generator) -> np.ndarray:
    return np.stack([white(n, rng), white(n, rng)])


def circ_dist(t: np.ndarray, center: float, loop: float) -> np.ndarray:
    return ((t - center + loop * 0.5) % loop) - loop * 0.5


def gust_curve(n: int, rng: np.random.Generator, loop: float, count: int, widths: tuple, depth: float) -> np.ndarray:
    t = tt(n)
    g = np.zeros(n)
    for _ in range(count):
        d = circ_dist(t, rng.uniform(0, loop), loop)
        w = rng.uniform(*widths)
        g += np.where(np.abs(d) < w * 0.5, np.cos(np.pi * d / w) ** 2, 0.0)
    g = g / (g.max() + 1e-9)
    return (1.0 - depth) + depth * g


def drone(loop: float, midis, rng, voices=3, cents=9.0, partial_count=12, tilt=1.3, lfo_depth=0.5,
          max_hz=2600.0, even_cut=1.0) -> np.ndarray:
    n = int(round(loop * SR))
    t = tt(n)
    out = np.zeros((2, n))
    offs = np.linspace(-cents, cents, voices) if voices > 1 else np.zeros(1)
    for m in midis:
        f0 = midi_hz(m)
        for vi in range(voices):
            f = f0 * 2.0 ** (offs[vi] / 1200.0)
            sig = np.zeros(n)
            for k in range(1, partial_count + 1):
                fk = snap(f * k, loop)
                if fk > max_hz:
                    break
                a = k ** (-tilt) * (even_cut if k % 2 == 0 else 1.0)
                lfo = 1.0 + lfo_depth * np.sin(TAU * int(rng.integers(1, 5)) * t / loop + rng.uniform(0, TAU))
                sig += a * lfo * np.sin(TAU * fk * t + rng.uniform(0, TAU))
            pan = -0.6 + 1.2 * vi / (voices - 1) if voices > 1 else 0.0
            out += to_stereo(sig, pan)
    return out


def pad(loop: float, chords, rng, partial_count=5, overlap=1.35) -> np.ndarray:
    """Slow chord swells following a progression; first chord's attack overlaps the last release."""
    n = int(round(loop * SR))
    t = tt(n)
    out = np.zeros((2, n))
    seg = loop / len(chords)
    for ci, chord in enumerate(chords):
        d = circ_dist(t, (ci + 0.5) * seg, loop)
        half = seg * overlap * 0.5
        env = np.where(np.abs(d) < half, np.cos(np.pi * 0.5 * d / half) ** 2, 0.0)
        for m in chord:
            for vi, cents in enumerate((-7.0, 6.0)):
                f = midi_hz(m) * 2.0 ** (cents / 1200.0)
                sig = np.zeros(n)
                for k in range(1, partial_count + 1):
                    sig += (k ** -1.5) * np.sin(TAU * snap(f * k, loop) * t + rng.uniform(0, TAU))
                out += to_stereo(sig * env, -0.5 if vi == 0 else 0.5)
    return out


def wind(loop: float, rng, bands, gusts=6, widths=(3.0, 7.5), depth=0.75, whistles=(), whistle_gain=0.12) -> np.ndarray:
    n = int(round(loop * SR))
    out = np.zeros((2, n))
    for lo, hi in bands:
        # Independent noise per band: bands cut from one noise cancel at their crossover.
        out += bp(stereo_noise(n, rng), lo, hi, 2, circular=True)
    g = gust_curve(n, rng, loop, gusts, widths, depth)
    out *= np.stack([g, np.roll(g, int(1.7 * SR))])
    for fw, q in whistles:
        w = resonator(stereo_noise(n, rng), fw, q, circular=True)
        w /= (np.std(w) + 1e-9)
        out += whistle_gain * w * np.stack([g ** 2, np.roll(g, int(2.6 * SR)) ** 2]) * np.std(out)
    return out


def beams(loop: float, rng, freqs, gain=0.5) -> np.ndarray:
    """Wind across hollow beams: narrow resonances that swell in and out."""
    n = int(round(loop * SR))
    t = tt(n)
    out = np.zeros((2, n))
    for i, f in enumerate(freqs):
        r = resonator(stereo_noise(n, rng), f, 35.0, circular=True)
        r /= (np.std(r) + 1e-9)
        lfo = 0.5 + 0.5 * np.sin(TAU * int(rng.integers(1, 4)) * t / loop + rng.uniform(0, TAU))
        out += gain * r * (lfo ** 1.5)
    return out


def roar(loop: float, rng, mid_gain=0.6, hiss_gain=0.05, crackle_rate=16.0, crackle_gain=0.5) -> np.ndarray:
    """Furnace: brown low rumble + modulated mid body + sparse crackle + faint hiss."""
    n = int(round(loop * SR))
    t = tt(n)
    out = np.zeros((2, n))
    for ch in range(2):
        low = lp(brown(n, rng), 170.0, 2, circular=True)
        mid = bp(pink(n, rng), 250.0, 900.0, 2, circular=True)
        mod = 0.65 + 0.35 * sum(np.sin(TAU * int(rng.integers(3, 20)) * t / loop + rng.uniform(0, TAU)) for _ in range(3)) / 3.0
        hiss = bp(white(n, rng), 2800.0, 6500.0, 2, circular=True)
        out[ch] = low * 1.0 + mid * mid_gain * mod + hiss * hiss_gain
        imp = np.zeros(n)
        idx = rng.integers(0, n, int(crackle_rate * loop))
        imp[idx] = rng.exponential(1.0, len(idx)) * rng.choice([-1.0, 1.0], len(idx))
        kernel = hp(white(600, rng), 2200.0) * np.exp(-np.arange(600) / (0.006 * SR))
        spec = np.fft.rfft(imp) * np.fft.rfft(kernel, n=n)
        out[ch] += crackle_gain * np.fft.irfft(spec, n=n) * 0.7
    return out


def water(loop: float, rng, bubbles=0.35) -> np.ndarray:
    """Wet undercroft bed: flowing noise band with flutter + bubbling band."""
    n = int(round(loop * SR))
    t = tt(n)
    out = np.zeros((2, n))
    for ch in range(2):
        flow = bp(pink(n, rng), 350.0, 1500.0, 2, circular=True)
        flut = 0.6 + 0.4 * np.sin(TAU * int(rng.integers(30, 70)) * t / loop + rng.uniform(0, TAU))
        slow = 0.7 + 0.3 * np.sin(TAU * int(rng.integers(1, 4)) * t / loop + rng.uniform(0, TAU))
        bub = bp(white(n, rng), 600.0, 2400.0, 2, circular=True)
        bub *= np.clip(np.sin(TAU * int(rng.integers(90, 160)) * t / loop + rng.uniform(0, TAU)), 0.0, 1.0) ** 3
        out[ch] = flow * flut * slow + bubbles * bub
    return out


def drip_layer(loop: float, rng, count: int, f_lo: float, f_hi: float, gain: float) -> np.ndarray:
    n = int(round(loop * SR))
    out = np.zeros((2, n))
    for _ in range(count):
        f = rng.uniform(f_lo, f_hi)
        dn = int(0.3 * SR)
        t = tt(dn)
        ft = f * (1.0 + 2.2 * (1.0 - np.exp(-t / 0.012)))
        drop = np.sin(osc_phase(ft)) * np.exp(-t / 0.032) * attack_env(dn, 0.001)
        place(out, drop, int(rng.uniform(0, n)), gain * rng.uniform(0.35, 1.0), rng.uniform(-0.7, 0.7), wrap=True)
    return out


def hum(loop: float, f: float, rng, level=1.0) -> np.ndarray:
    n = int(round(loop * SR))
    t = tt(n)
    sig = np.zeros(n)
    for k, a in enumerate([1.0, 0.55, 0.5, 0.3, 0.25, 0.15, 0.1], start=1):
        sig += a * np.sin(TAU * snap(f * k, loop) * t + rng.uniform(0, TAU))
    sig *= 1.0 + 0.12 * np.sin(TAU * 3 * t / loop)
    return to_stereo(sig * level, 0.0) + 0.0


def heartbeat(loop: float, rng, bpm=60.0, f=54.0, gain=1.0) -> np.ndarray:
    n = int(round(loop * SR))
    out = np.zeros((2, n))
    beat = SR * 60.0 / bpm
    for b in range(int(round(loop * bpm / 60.0))):
        dn = int(0.5 * SR)
        t = tt(dn)
        lub = sine_sweep(dn, f, f * 1.9, 0.04) * np.exp(-t / 0.11) * attack_env(dn, 0.004)
        place(out, lub, int(b * beat), gain, 0.0, wrap=True)
        place(out, lub * 0.62, int(b * beat + 0.31 * SR), gain, 0.0, wrap=True)
    return out


def tick_layer(loop: float, rng, bpm: float, gain: float, accents) -> np.ndarray:
    n = int(round(loop * SR))
    out = np.zeros((2, n))
    eighth = SR * 60.0 / bpm / 2.0
    count = int(round(loop * bpm / 60.0 * 2.0))
    for i in range(count):
        a = accents[i % len(accents)]
        place(out, tick(rng, 2400.0 + rng.uniform(-300, 300)), int(i * eighth), gain * a, rng.uniform(-0.5, 0.5), wrap=True)
    return out


def choir(loop: float, midis, rng, level=1.0, vowel=(700.0, 1100.0, 2500.0)) -> np.ndarray:
    """Vowel-filtered saw swell (cathedral): vibrato is a whole number of cycles per loop."""
    n = int(round(loop * SR))
    t = tt(n)
    out = np.zeros((2, n))
    for ci, m in enumerate(midis):
        f = snap(midi_hz(m), loop)
        vib = 1.0 + 0.004 * np.sin(TAU * 200 * t / loop + ci)
        saw = saw_from_phase(osc_phase(np.full(n, f) * vib))
        voiced = sum(bp(saw, fc * 0.85, fc * 1.18, 2, circular=True) * g for fc, g in zip(vowel, (1.0, 0.6, 0.25)))
        swell = 0.55 + 0.45 * np.sin(TAU * int(rng.integers(1, 4)) * t / loop + rng.uniform(0, TAU))
        out += to_stereo(voiced * swell, -0.4 + 0.8 * ci / max(1, len(midis) - 1))
    return out * level


# --- stems ------------------------------------------------------------------

def finish_loop(x: np.ndarray, lufs: float, lp_hz: float = 9000.0, hp_hz: float = 38.0) -> np.ndarray:
    x = x - x.mean(axis=-1, keepdims=True)
    x = sub_cut(x, hp_hz, circular=True)
    x = lp(x, lp_hz, 2, circular=True)
    return normalize_lufs(x, lufs, max_peak_db=-1.5)


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(np.square(x)))) + 1e-12


def mix_in(dst: np.ndarray, src: np.ndarray, rel_db: float) -> None:
    """Add src at rel_db relative to dst's current RMS."""
    dst += src * (rms(dst) / rms(src)) * db_to_lin(rel_db)


def bed_stem(name: str, sp: dict) -> np.ndarray:
    rng = rng_for(name + ":bed")
    x = drone(LOOP, sp["drone"], rng, **sp.get("drone_kw", {}))
    base = x.copy()
    if "pad" in sp:
        mix_in(x, pad(LOOP, sp["pad"], rng), sp.get("pad_db", -7.0))
    for layer in sp.get("layers", []):
        kind = layer["kind"]
        if kind == "wind":
            tex = wind(LOOP, rng, layer["bands"], layer.get("gusts", 6), layer.get("widths", (3.0, 7.5)),
                       layer.get("depth", 0.75), layer.get("whistles", ()), layer.get("whistle_gain", 0.12))
        elif kind == "beams":
            tex = beams(LOOP, rng, layer["freqs"])
        elif kind == "roar":
            tex = roar(LOOP, rng, **layer.get("kw", {}))
        elif kind == "water":
            tex = water(LOOP, rng, layer.get("bubbles", 0.35))
        elif kind == "drips":
            tex = drip_layer(LOOP, rng, layer["count"], layer["lo"], layer["hi"], 1.0)
        elif kind == "hum":
            tex = hum(LOOP, layer["f"], rng)
        elif kind == "heartbeat":
            tex = heartbeat(LOOP, rng, layer.get("bpm", 60.0), layer.get("f", 54.0))
        elif kind == "ticks":
            tex = tick_layer(LOOP, rng, layer["bpm"], 1.0, layer.get("accents", [1.0, 0.35, 0.6, 0.35]))
        elif kind == "choir":
            tex = choir(LOOP, layer["midis"], rng, vowel=layer.get("vowel", (700.0, 1100.0, 2500.0)))
        else:
            raise ValueError(kind)
        mix_in(x, tex, layer["db"])
    ir = reverb_ir(sp.get("bed_rt60", 3.0), rng, damping=sp.get("damp", 2600.0))
    x = reverb(x, ir, sp.get("bed_wet", 0.3), circular=True, dry=1.0)
    del base
    return finish_loop(x, LUFS["bed"], lp_hz=sp.get("bed_lp", 7500.0))


def scale_note(root: int, scale, degree: int) -> int:
    return root + 12 * (degree // len(scale)) + scale[degree % len(scale)]


def make_phrases(rng, loop: float, sp: dict) -> list:
    out = []
    p = sp["phrases"]
    seg = loop / p
    lo, hi = sp["register"]
    for i in range(p):
        t = i * seg + rng.uniform(0.08, 0.35) * seg
        deg = int(rng.choice([0, 2, 4, 7, 9])) + 7 * int(rng.integers(0, 2))
        for j in range(int(rng.integers(sp["notes"][0], sp["notes"][1] + 1))):
            m = scale_note(sp["root"], sp["scale"], deg)
            while m < lo:
                m += 12
            while m > hi:
                m -= 12
            vel = rng.uniform(0.42, 0.74) * (1.0 if j == 0 else 0.88)
            out.append((t, m, vel))
            if rng.random() < sp.get("hollow", 0.35):
                out.append((t + 0.025, m + 7 if m + 7 <= hi else m - 5, vel * 0.55))
            if rng.random() < sp.get("octave", 0.2) and m - 12 >= lo - 12:
                out.append((t + 0.01, m - 12, vel * 0.5))
            deg += int(rng.choice([-2, -1, -1, 0, 1, 1, 2, 3]))
            t += rng.uniform(*sp["gap"])
    return out


def keys_stem(name: str, sp: dict) -> np.ndarray:
    rng = rng_for(name + ":keys")
    loop = float(sp["keys_len"])
    n = int(round(loop * SR))
    buf = np.zeros((2, n))
    notes = sp["motif"] if "motif" in sp else make_phrases(rng, loop, sp)
    for t, m, vel in notes:
        place(buf, instrument(sp["tone"], m, vel, rng), int(t * SR), 1.0, rng.uniform(-0.3, 0.3), wrap=True)
    ir = reverb_ir(sp.get("rt60", 4.5), rng, damping=sp.get("damp", 3000.0))
    buf = reverb(buf, ir, sp.get("wet", 0.6), circular=True, dry=1.0)
    lufs = LUFS["title_keys"] if name == "title" else LUFS["keys"]
    return finish_loop(buf, lufs, lp_hz=sp.get("keys_lp", 9500.0), hp_hz=60.0)


def lane_variants(rng, lane: dict, count: int = 3) -> list:
    fn = VOICES[lane["kind"]]
    return [fn(rng, **lane.get("kw", {})) for _ in range(count)]


def pattern_stem(name: str, sp: dict, role: str) -> np.ndarray:
    """Percussion / riff layer on a 16-step grid; loop length is a whole number of bars."""
    rng = rng_for(name + ":" + role)
    bpm = sp["bpm"]
    beats = LOOP * bpm / 60.0
    bars = int(round(beats / 4.0))
    assert abs(bars * 4.0 - beats) < 1e-6, (name, bpm, beats)
    step = SR * 60.0 / bpm / 4.0
    buf = np.zeros((2, N))
    for lane_name, lane in sp["lanes"].items():
        variants = lane_variants(rng, lane)
        pats = lane["pats"]
        for bar in range(bars):
            pat = pats[bar % len(pats)]
            fill = lane.get("fill")
            if fill and bar % fill[0] == fill[0] - 1:
                pat = fill[1]
            assert len(pat) == 16, (name, lane_name, pat)
            for si, ch in enumerate(pat):
                if ch == ".":
                    continue
                vel = {"x": 1.0, "o": 0.55, "X": 1.2}[ch]
                pos = int(round((bar * 16 + si) * step)) + int(rng.integers(-50, 50))
                one = variants[int(rng.integers(0, len(variants)))]
                place(buf, one, pos, vel * lane.get("gain", 1.0), lane.get("pan", 0.0) + rng.uniform(-0.12, 0.12), wrap=True)
    ir = reverb_ir(sp.get("rt60", 1.8), rng, damping=2800.0)
    buf = reverb(buf, ir, sp.get("wet", 0.18), circular=True, dry=1.0)
    target = LUFS["pulse"] if role == "pulse" else (LUFS["boss_bed"] if role == "bed" else LUFS["boss_hi"])
    return finish_loop(buf, target, lp_hz=sp.get("lp", 11000.0), hp_hz=40.0)


# --- theme table ------------------------------------------------------------

def L_(kind, db, **kw):
    d = {"kind": kind, "db": db}
    d.update(kw)
    return d


def kick_lane(pats, gain=1.0, **kw):
    return {"kind": "kick", "pats": pats, "gain": gain, "pan": 0.0, "kw": kw}


def lane(kind, pats, gain=0.5, pan=0.0, fill=None, **kw):
    d = {"kind": kind, "pats": pats, "gain": gain, "pan": pan, "kw": kw}
    if fill:
        d["fill"] = fill
    return d


TITLE_MOTIF = [
    # (seconds, midi, velocity): D minor, a slow falling-and-rising figure, two phrases per loop.
    (1.5, 62, 0.62), (4.2, 65, 0.52), (6.9, 69, 0.58), (10.6, 67, 0.50), (13.4, 65, 0.48), (16.8, 64, 0.52),
    (20.5, 62, 0.64), (20.52, 50, 0.45),
    (27.0, 57, 0.50), (29.6, 62, 0.56), (32.4, 65, 0.52), (35.5, 69, 0.58), (38.2, 70, 0.50), (41.5, 69, 0.46),
    (44.6, 67, 0.50), (46.2, 62, 0.58),
]

THEMES = {
    "title": dict(
        drone=[38, 45, 50], drone_kw=dict(voices=4, cents=11.0, lfo_depth=0.55),
        pad=[[50, 53, 57], [46, 50, 53], [43, 50, 55], [45, 52, 57]], pad_db=-6.0,
        layers=[L_("beams", -26.0, freqs=[440.0, 660.0, 880.0])],
        bed_rt60=4.0, bed_wet=0.35,
        keys_len=48, tone="piano", motif=TITLE_MOTIF, rt60=6.0, wet=0.7,
    ),
    "graveyard": dict(
        drone=[40, 47, 52], drone_kw=dict(voices=3, cents=8.0),
        pad=[[52, 55, 59], [48, 52, 55], [50, 54, 57], [47, 50, 54]], pad_db=-8.0,
        layers=[L_("wind", -7.0, bands=[(180.0, 520.0), (500.0, 1100.0)], gusts=6, whistles=[(640.0, 30.0), (1010.0, 40.0)])],
        bed_rt60=3.4, bed_wet=0.28,
        keys_len=52, tone="piano", root=52, scale=AEOLIAN, register=(52, 79), phrases=7, notes=(3, 5),
        gap=(1.1, 2.1), hollow=0.45, rt60=5.0, wet=0.6,
        bpm=90, rt_p=1.8,
        lanes={
            "kick": kick_lane(["x.......x.....o.", "x.......x...o..."], 1.0, f_hi=140, f_lo=48, decay=0.34, drive=1.8),
            "anvil": lane("anvil", ["....x.......x...", "....x.......x.x."], 0.55, 0.25, f=520, decay=0.5),
            "tom": lane("tom", ["................", "..........o.o..."], 0.5, -0.3, f=88),
            "scrape": lane("scrape", ["x...............", "................", "................", "................"], 0.35, 0.4),
        },
    ),
    "undercroft": dict(
        drone=[36, 43, 48], drone_kw=dict(voices=5, cents=14.0, lfo_depth=0.6, tilt=1.15),
        pad=[[48, 51, 55], [44, 48, 51], [46, 50, 53], [43, 46, 50]], pad_db=-8.0,
        layers=[L_("water", -9.0, bubbles=0.4), L_("drips", -12.0, count=24, lo=700.0, hi=1500.0)],
        bed_rt60=5.0, bed_wet=0.4, damp=2200.0,
        keys_len=56, tone="felt", root=48, scale=AEOLIAN, register=(48, 74), phrases=6, notes=(3, 5),
        gap=(1.3, 2.4), hollow=0.35, rt60=6.5, wet=0.7,
        bpm=78, rt60_p=2.4,
        lanes={
            "kick": kick_lane(["x.....x...x.....", "x.....x.....o..."], 0.9, f_hi=120, f_lo=44, decay=0.4, drive=1.4),
            "anvil": lane("anvil", ["........x.......", "........x.....o."], 0.5, -0.2, f=300, decay=0.7, bright=0.8),
            "tick": lane("tick", ["x..o..x..o..x..o", "..o..x..o..x..o."], 0.3, 0.3),
            "scrape": lane("scrape", ["x...............", "................", "........x.......", "................"], 0.3, -0.4, f0=500, f1=1600),
        },
    ),
    "town": dict(
        drone=[43, 50, 55], drone_kw=dict(voices=3, cents=10.0, tilt=1.2, even_cut=0.5),
        pad=[[55, 58, 62], [51, 55, 58], [53, 57, 60], [50, 53, 57]], pad_db=-9.0,
        layers=[L_("beams", -11.0, freqs=[330.0, 495.0, 660.0, 990.0]),
                L_("wind", -10.0, bands=[(200.0, 700.0)], gusts=7, whistles=[(780.0, 28.0)])],
        bed_rt60=2.6, bed_wet=0.22,
        keys_len=44, tone="honky", root=55, scale=DORIAN, register=(55, 81), phrases=8, notes=(3, 4),
        gap=(0.9, 1.7), hollow=0.5, rt60=3.4, wet=0.5,
        bpm=96,
        lanes={
            "kick": kick_lane(["x..x..x...x..x..", "x..x..x...x.o..."], 1.0, f_hi=150, f_lo=50, decay=0.3, drive=2.0),
            "clank": lane("clank", ["..x...x...x...x.", ".o..x...o..x..o."], 0.38, 0.35, f=1100),
            "snare": lane("snare", ["........x.......", "........x.....o."], 0.45, -0.1, body=170),
            "anvil": lane("anvil", ["x...............", "................"], 0.45, -0.3, f=460, decay=0.5),
        },
    ),
    "cathedral": dict(
        drone=[42, 49, 54], drone_kw=dict(voices=4, cents=7.0, tilt=0.9, partial_count=16, lfo_depth=0.4),
        pad=[[54, 57, 61], [50, 54, 57], [52, 56, 59], [49, 52, 56]], pad_db=-8.0,
        layers=[L_("choir", -9.0, midis=[54, 61, 66], vowel=(650.0, 1000.0, 2400.0))],
        bed_rt60=7.0, bed_wet=0.5, damp=2000.0,
        keys_len=60, tone="piano", root=54, scale=DORIAN, register=(54, 78), phrases=6, notes=(3, 5),
        gap=(1.5, 2.7), hollow=0.55, rt60=9.0, wet=0.75, keys_lp=8000.0,
        bpm=84, rt60_p=3.2,
        lanes={
            "tom": lane("tom", ["x.......x.......", "x.......x...o..."], 1.0, 0.0, f=70, decay=0.4),
            "anvil": lane("anvil", ["x...............", "........x......."], 0.5, 0.3, f=330, decay=1.1, bright=0.7),
            "kick": kick_lane(["........x.......", "................"], 0.7, f_hi=110, f_lo=46, decay=0.4, drive=1.3),
            "scrape": lane("scrape", ["................", "x...............", "................", "................"], 0.25, -0.4),
        },
        wet_p=0.3,
    ),
    "workshop": dict(
        drone=[33, 40, 45], drone_kw=dict(voices=3, cents=6.0, tilt=1.0, even_cut=0.6),
        pad=[[45, 48, 52], [41, 45, 48], [43, 47, 50], [40, 43, 47]], pad_db=-11.0,
        layers=[L_("hum", -8.0, f=100.0), L_("ticks", -14.0, bpm=72.0, accents=[1.0, 0.35, 0.6, 0.35, 0.85, 0.35, 0.5, 0.35]),
                L_("wind", -18.0, bands=[(250.0, 800.0)], gusts=4)],
        bed_rt60=1.8, bed_wet=0.2, damp=3500.0,
        keys_len=48, tone="metal", root=57, scale=AEOLIAN, register=(57, 84), phrases=7, notes=(2, 4),
        gap=(0.7, 1.6), hollow=0.25, rt60=2.4, wet=0.45,
        bpm=108,
        lanes={
            "kick": kick_lane(["x...x...x...x...", "x...x...x...x.o."], 1.0, f_hi=160, f_lo=52, decay=0.26, drive=2.8),
            "tick": lane("tick", ["x.x.x.x.x.x.x.x.", "x.xox.x.x.xox.x."], 0.32, 0.4),
            "anvil": lane("anvil", ["............x...", "............x.x."], 0.6, -0.2, f=640, decay=0.35),
            "rasp": lane("rasp", ["................", "................", "................", "x..............."], 0.5, 0.0, f=96, dur=0.4),
        },
    ),
    "bell_tower": dict(
        drone=[35, 42, 47], drone_kw=dict(voices=3, cents=9.0, tilt=1.1),
        pad=[[47, 50, 54], [43, 47, 50], [45, 49, 52], [42, 45, 49]], pad_db=-10.0,
        layers=[L_("wind", -5.0, bands=[(350.0, 1000.0), (900.0, 2200.0)], gusts=9, widths=(2.0, 5.0), depth=0.85,
                   whistles=[(880.0, 30.0), (1320.0, 36.0), (1760.0, 40.0)], whistle_gain=0.2)],
        bed_rt60=4.4, bed_wet=0.32,
        keys_len=52, tone="bell", root=47, scale=AEOLIAN, register=(47, 71), phrases=5, notes=(1, 3),
        gap=(2.2, 3.6), hollow=0.0, octave=0.0, rt60=7.0, wet=0.55,
        bpm=90,
        lanes={
            "toll": lane("toll", ["x...............", "................"], 0.8, 0.0, f=98),
            "kick": kick_lane(["x.......x.......", "x.......x...o..."], 0.85, f_hi=130, f_lo=47, decay=0.36, drive=1.8),
            "anvil": lane("anvil", ["....x.......x...", "....x.....x.x..."], 0.5, 0.3, f=600, decay=0.6),
            "clank": lane("clank", ["..o...o...o...o.", "o...o...o...o..."], 0.25, -0.4, f=1500),
        },
    ),
    "slag": dict(
        drone=[36, 42, 48], drone_kw=dict(voices=3, cents=12.0, tilt=1.05, lfo_depth=0.65),
        pad=[[48, 51, 54], [44, 48, 51], [43, 48, 51], [42, 46, 49]], pad_db=-10.0,
        layers=[L_("roar", -4.0, kw=dict(mid_gain=0.7, hiss_gain=0.06, crackle_rate=22.0, crackle_gain=0.6))],
        bed_rt60=2.8, bed_wet=0.22, damp=2400.0,
        keys_len=44, tone="metal", root=48, scale=PHRYGIAN, register=(36, 64), phrases=4, notes=(2, 3),
        gap=(1.8, 3.2), hollow=0.0, octave=0.5, rt60=3.2, wet=0.5,
        bpm=96,
        lanes={
            "anvil": lane("anvil", ["x..x..x.x..x..x.", "x..x..x.x..x.xx."], 0.8, 0.0, f=470, decay=0.5),
            "kick": kick_lane(["x.......x.......", "x.......x.....o."], 1.0, f_hi=140, f_lo=46, decay=0.36, drive=2.4),
            "rasp": lane("rasp", ["................", "............x...", "................", "........x......."], 0.55, 0.3, f=90, dur=0.5),
            "scrape": lane("scrape", ["..o...o...o...o.", "o...o...o...o..."], 0.22, -0.4, f0=900, f1=3000),
        },
    ),
    "ramparts": dict(
        drone=[38, 45, 50], drone_kw=dict(voices=4, cents=13.0, tilt=0.95, partial_count=14, lfo_depth=0.65, even_cut=0.7),
        pad=[[50, 53, 57], [46, 50, 53], [48, 52, 55], [45, 48, 52]], pad_db=-7.0,
        layers=[L_("wind", -6.0, bands=[(200.0, 900.0), (700.0, 1800.0)], gusts=7, whistles=[(700.0, 25.0)], whistle_gain=0.1)],
        bed_rt60=4.0, bed_wet=0.3,
        keys_len=56, tone="piano", root=50, scale=AEOLIAN, register=(50, 76), phrases=6, notes=(3, 4),
        gap=(1.0, 1.9), hollow=0.9, octave=0.6, rt60=5.5, wet=0.6,
        bpm=102,
        lanes={
            "kick": kick_lane(["x...x...x...x...", "x...x...x...x.o."], 0.9, f_hi=130, f_lo=48, decay=0.3, drive=1.6),
            "snare": lane("snare", ["o...x...o...x...", "o...x...o...x.xo"], 0.6, 0.1, body=175),
            "chug": lane("chug", ["x.xox.xox.xox.xo", "x.xox.xox.xoxxxo"], 0.7, 0.0, midi=26, dur=0.22),
            "anvil": lane("anvil", ["x...............", "................"], 0.45, -0.3, f=400, decay=0.6),
        },
    ),
    "core": dict(
        drone=[37, 38, 44, 49], drone_kw=dict(voices=3, cents=10.0, tilt=1.0, lfo_depth=0.7),
        pad=[[49, 52, 56], [50, 53, 56], [45, 49, 52], [49, 53, 56]], pad_db=-9.0,
        layers=[L_("roar", -8.0, kw=dict(mid_gain=0.5, hiss_gain=0.04, crackle_rate=12.0, crackle_gain=0.4)),
                L_("heartbeat", -7.0, bpm=60.0, f=54.0),
                L_("wind", -16.0, bands=[(200.0, 600.0)], gusts=5)],
        bed_rt60=6.0, bed_wet=0.4, damp=2200.0,
        keys_len=56, tone="piano", root=49, scale=LOCRIAN, register=(49, 75), phrases=5, notes=(2, 4),
        gap=(1.4, 2.6), hollow=0.4, octave=0.3, rt60=8.0, wet=0.7,
        bpm=120,
        lanes={
            "kick": kick_lane(["x.x...x.x.x...x.", "x.x...x.x.x.o..o"], 1.0, f_hi=150, f_lo=46, decay=0.32, drive=2.6),
            "anvil": lane("anvil", ["..x...x...x...x.", "..x...x...x..xx."], 0.6, 0.0, f=520, decay=0.55),
            "rasp": lane("rasp", ["................", "................", "x...............", "............x..."], 0.55, 0.35, f=92, dur=0.5),
            "chug": lane("chug", ["xxoxxxoxxxoxxxox", "xxoxxxoxxxoxxxxx"], 0.55, 0.0, midi=25, dur=0.2),
            "scrape": lane("scrape", ["o...............", "................"], 0.25, -0.4),
        },
    ),
}

BOSSES = {
    "boss_executioner": dict(
        drone=[28, 35, 40], drone_kw=dict(voices=3, cents=14.0, tilt=1.0, lfo_depth=0.6),
        pad=[[40, 43, 47], [41, 44, 48], [40, 43, 47], [38, 42, 45]], pad_db=-9.0,
        layers=[L_("roar", -9.0, kw=dict(mid_gain=0.5, hiss_gain=0.04, crackle_rate=14.0, crackle_gain=0.4))],
        bed_rt60=2.4, bed_wet=0.2,
        bpm=96,
        lanes={
            "kick": kick_lane(["x..x..x...x.x...", "x..x..x...x.x.o."], 1.0, f_hi=150, f_lo=46, decay=0.34, drive=3.0),
            "snare": lane("snare", ["....x.......x...", "....x.......x.xo"], 0.6, 0.1, body=170),
            "anvil": lane("anvil", ["x.......x.......", "x.......x.x....."], 0.8, 0.0, f=440, decay=0.6),
            "chug": lane("chug", ["x.xxx.xxx.xxx.xx", "x.xxx.xxx.xxx.x."], 0.6, 0.0, midi=28, dur=0.22),
            "tom": lane("tom", ["................", "................", "................", "............xxxx"], 0.6, -0.3, f=85),
            "rasp": lane("rasp", ["................", "................", "................", "x..............."], 0.6, 0.3, f=86, dur=0.5),
        },
        hi_lanes={
            "scrape": lane("scrape", ["x.......o.......", "........o.o....."], 0.5, 0.4, f0=1000, f1=3200),
            "clank": lane("clank", ["..x...x...x...x.", "o.x.o.x.o.x.o.x."], 0.4, -0.4, f=1400),
            "snare": lane("snare", ["................", "o.o.o.o.o.o.o.o."], 0.35, 0.2, body=210),
            "rasp": lane("rasp", ["x...............", "........x......."], 0.6, -0.2, f=104, dur=0.45),
        },
    ),
    "boss_nightmare": dict(
        drone=[25, 31, 37, 43], drone_kw=dict(voices=3, cents=16.0, tilt=0.95, lfo_depth=0.7),
        pad=[[49, 52, 55], [50, 53, 56], [47, 50, 54], [49, 52, 55]], pad_db=-8.0,
        layers=[L_("roar", -8.0, kw=dict(mid_gain=0.55, hiss_gain=0.05, crackle_rate=18.0, crackle_gain=0.5)),
                L_("heartbeat", -8.0, bpm=60.0, f=54.0)],
        bed_rt60=3.0, bed_wet=0.22,
        bpm=108,
        lanes={
            "kick": kick_lane(["x.xx.xx.x.xx.xx.", "x.xx.xx.x.xx.xxx"], 1.0, f_hi=140, f_lo=46, decay=0.26, drive=3.2),
            "tom": lane("tom", ["....x.......x...", "....x.....x.x.x."], 0.7, -0.25, f=80),
            "anvil": lane("anvil", ["x...............", "........x......."], 0.7, 0.2, f=380, decay=0.8),
            "chug": lane("chug", ["xxxxxxxxxxxxxxxx", "xoxxxoxxxoxxxoxx"], 0.5, 0.0, midi=25, dur=0.16),
            "rasp": lane("rasp", ["................", "x...............", "................", "........x......."], 0.6, 0.3, f=84, dur=0.55),
        },
        hi_lanes={
            "snare": lane("snare", ["x...x...x...x...", "x.x.x.x.x.x.xxxx"], 0.5, 0.0, body=200),
            "scrape": lane("scrape", ["x...............", "................", "........x.......", "................"], 0.6, -0.4, f0=1200, f1=3600),
            "clank": lane("clank", ["x.x.x.x.x.x.x.x.", "o.o.o.o.o.o.o.o."], 0.35, 0.4, f=1700),
            "rasp": lane("rasp", ["x.......x.......", "x...x...x...x..."], 0.65, 0.0, f=100, dur=0.45),
        },
    ),
}

ENDING = dict(
    drone=[38, 45, 50], drone_kw=dict(voices=4, cents=9.0, tilt=1.2, lfo_depth=0.45),
    pad=[[50, 54, 57], [47, 50, 54], [43, 47, 50], [45, 49, 52]], pad_db=-5.5,
    layers=[L_("beams", -28.0, freqs=[440.0, 660.0])],
    bed_rt60=5.0, bed_wet=0.4,
    keys_len=48, tone="felt", root=50, scale=DORIAN, register=(50, 81), phrases=6, notes=(3, 5),
    gap=(1.3, 2.4), hollow=0.5, octave=0.3, rt60=7.0, wet=0.7,
)


# --- stingers (one-shot, linear convolution) --------------------------------

def _stinger_buf(seconds: float) -> np.ndarray:
    return np.zeros((2, int(seconds * SR)))


def _swell(seconds: float, midis, rng, partials_n=4, shape=2.2) -> np.ndarray:
    n = int(seconds * SR)
    t = tt(n)
    env = np.sin(np.linspace(0.0, np.pi, n)) ** shape
    sig = np.zeros(n)
    for m in midis:
        f = midi_hz(m)
        for k in range(1, partials_n + 1):
            for c in (-6.0, 7.0):
                sig += (k ** -1.4) * np.sin(TAU * f * k * 2.0 ** (c / 1200.0) * t + rng.uniform(0, TAU))
    return to_stereo(lp(sig * env, 1800.0, 2))


def _finish_stinger(buf: np.ndarray, seconds: float, rng, rt60: float, wet: float, fade: float = 0.6) -> np.ndarray:
    buf = reverb(buf, reverb_ir(rt60, rng), wet, circular=False, dry=1.0)
    buf = buf[:, :int(seconds * SR)]
    buf = fade_edges(buf, 0.003, fade)
    buf = sub_cut(buf, 40.0)
    buf = lp(buf, 11000.0, 2)
    return normalize_lufs(buf, LUFS["stinger"], max_peak_db=-2.0)


def stinger_chapter(rng):
    buf = _stinger_buf(6.0)
    place(buf, _swell(4.5, [38, 45], rng), 0, 1.0)
    for t, m, v in [(0.5, 62, 0.8), (1.9, 69, 0.6), (3.0, 74, 0.45)]:
        place(buf, piano_note(m, v, rng, bright=0.5), int(t * SR), 0.9, rng.uniform(-0.2, 0.2))
    place(buf, bell_note(midi_hz(50), 0.5, rng, 5.0), int(0.5 * SR), 0.5)
    return _finish_stinger(buf, 6.0, rng, 4.5, 0.55)


def stinger_boss_intro(rng):
    buf = _stinger_buf(6.5)
    place(buf, anvil(rng, 300.0, 1.1, 2.5), 0, 1.0)
    place(buf, kick(rng, 120.0, 44.0, 0.05, 0.5, 2.5), 0, 1.0)
    place(buf, _swell(4.2, [40, 46, 52], rng, 6, 3.0), int(0.8 * SR), 0.8)
    place(buf, scrape(rng, 1.2, 600.0, 2800.0), int(1.2 * SR), 0.5, 0.3)
    place(buf, anvil(rng, 440.0, 1.3, 2.5), int(4.3 * SR), 1.0)
    place(buf, kick(rng, 130.0, 44.0, 0.05, 0.6, 3.0), int(4.3 * SR), 1.2)
    return _finish_stinger(buf, 6.5, rng, 3.5, 0.45, 0.9)


def stinger_boss_down(rng):
    buf = _stinger_buf(7.5)
    place(buf, kick(rng, 110.0, 42.0, 0.06, 0.7, 2.0), 0, 1.3)
    place(buf, anvil(rng, 280.0, 2.2, 5.0, 0.9), 0, 0.9)
    place(buf, _swell(5.5, [38, 45, 50, 53], rng), int(1.0 * SR), 0.6)
    for t, m, v in [(2.0, 62, 0.7), (3.4, 65, 0.6), (4.8, 69, 0.55)]:
        place(buf, piano_note(m, v, rng, bright=0.4), int(t * SR), 0.8)
    return _finish_stinger(buf, 7.5, rng, 5.0, 0.6, 1.2)


def stinger_ability(rng):
    buf = _stinger_buf(4.0)
    for i, m in enumerate([74, 77, 81, 86, 89]):
        place(buf, piano_note(m, 0.62, rng, bright=0.95, decay=0.7, hammer=0.05, max_len=3.0), int((0.1 + 0.16 * i) * SR), 0.8, -0.4 + 0.2 * i)
    n = int(2.5 * SR)
    shim = hp(white(n, rng), 3200.0) * np.sin(np.linspace(0.0, np.pi, n)) ** 2 * 0.07
    place(buf, to_stereo(lp(shim, 9000.0)), int(0.3 * SR), 1.0)
    place(buf, bell_note(midi_hz(62), 0.4, rng, 3.5), 0, 0.5)
    return _finish_stinger(buf, 4.0, rng, 3.2, 0.5, 0.8)


def stinger_death(rng):
    buf = _stinger_buf(6.5)
    n = int(1.6 * SR)
    t = tt(n)
    rise = hp(white(n, rng), 2500.0) * (t / 1.6) ** 2.5 * 0.2
    place(buf, to_stereo(lp(rise, 9000.0)), 0, 1.0)
    place(buf, kick(rng, 100.0, 46.0, 0.08, 0.9, 2.2), int(1.6 * SR), 1.2)
    place(buf, anvil(rng, 240.0, 1.6, 4.0, 0.7), int(1.6 * SR), 0.7)
    dn = int(4.5 * SR)
    td = tt(dn)
    fall = np.sin(osc_phase(glide(dn, 230.0, 70.0))) * np.exp(-td / 1.6)
    place(buf, to_stereo(lp(fall, 500.0)), int(1.6 * SR), 0.5)
    place(buf, piano_note(38, 0.7, rng, bright=0.25), int(2.0 * SR), 0.8)
    return _finish_stinger(buf, 6.5, rng, 5.0, 0.6, 1.5)


def stinger_rest(rng):
    buf = _stinger_buf(5.5)
    place(buf, _swell(4.0, [45, 52], rng), 0, 0.6)
    for t, m, v in [(0.3, 57, 0.55), (0.9, 64, 0.5), (1.6, 69, 0.5), (2.5, 72, 0.4)]:
        place(buf, piano_note(m, v, rng, bright=0.3), int(t * SR), 0.8, rng.uniform(-0.2, 0.2))
    n = int(4.0 * SR)
    imp = np.zeros(n)
    idx = rng.integers(0, n, 70)
    imp[idx] = rng.exponential(1.0, len(idx))
    kern = hp(white(500, rng), 2000.0) * np.exp(-np.arange(500) / (0.006 * SR))
    crackle = np.convolve(imp, kern)[:n] * np.exp(-np.linspace(0, 3, n)) * 0.08
    place(buf, to_stereo(crackle), 0, 1.0)
    return _finish_stinger(buf, 5.5, rng, 3.6, 0.45, 1.0)


def _ending(rng, chord_seq, notes, pad_notes, seconds, rt60, extra=None):
    buf = _stinger_buf(seconds)
    place(buf, _swell(seconds * 0.85, pad_notes, rng, 5, 1.6), 0, 0.8)
    for t, m, v in notes:
        place(buf, piano_note(m, v, rng, bright=0.35), int(t * SR), 0.85, rng.uniform(-0.3, 0.3))
    if extra:
        extra(buf)
    return _finish_stinger(buf, seconds, rng, rt60, 0.65, 3.0)


def stinger_ending_give(rng):
    notes = [(0.5 + 0.55 * i, m, 0.5 + 0.03 * i) for i, m in enumerate([62, 66, 69, 74, 76, 78, 81, 86])]
    return _ending(rng, None, notes, [38, 45, 50, 54], 14.0, 7.0,
                   lambda b: place(b, bell_note(midi_hz(74), 0.5, rng, 8.0), int(5.0 * SR), 0.5))


def stinger_ending_keep(rng):
    notes = [(0.8, 62, 0.6), (2.6, 69, 0.5), (4.6, 64, 0.55), (6.8, 67, 0.5), (9.0, 62, 0.45), (10.2, 50, 0.5)]
    def extra(b):
        n = int(10 * SR)
        imp = np.zeros(n)
        idx = rng.integers(0, n, 90)
        imp[idx] = rng.exponential(1.0, len(idx))
        kern = hp(white(500, rng), 1800.0) * np.exp(-np.arange(500) / (0.006 * SR))
        place(b, to_stereo(np.convolve(imp, kern)[:n] * 0.05), int(1.0 * SR), 1.0)
    return _ending(rng, None, notes, [38, 45, 50, 52], 14.0, 6.5, extra)


def stinger_ending_snuff(rng):
    notes = [(0.6, 57, 0.55), (3.4, 52, 0.5), (7.2, 45, 0.5)]
    def extra(b):
        place(b, bell_note(midi_hz(45), 0.7, rng, 9.0, 1.2), int(1.0 * SR), 0.7)
        n = int(11 * SR)
        w = lp(white(n, rng), 700.0) * np.sin(np.linspace(0.0, np.pi, n)) ** 2 * 0.05
        place(b, to_stereo(w), int(0.5 * SR), 1.0)
        place(b, kick(rng, 90.0, 42.0, 0.08, 0.8, 1.5), int(11.2 * SR), 0.5)
    return _ending(rng, None, notes, [33, 40, 45], 14.0, 8.0, extra)


STINGERS = {"chapter": stinger_chapter, "boss_intro": stinger_boss_intro, "boss_down": stinger_boss_down,
            "ability": stinger_ability, "death": stinger_death, "rest": stinger_rest,
            "ending_give": stinger_ending_give, "ending_keep": stinger_ending_keep,
            "ending_snuff": stinger_ending_snuff}


# --- task runner ------------------------------------------------------------

def _fixup_pattern_spec(sp: dict) -> dict:
    sp = dict(sp)
    if "rt60_p" in sp:
        sp["rt60"] = sp["rt60_p"]
    return sp


def build_task(task: tuple, quality: float) -> dict:
    kind, name, stem = task
    t0 = time.time()
    if kind == "theme":
        sp = THEMES[name]
        if stem == "bed":
            x = bed_stem(name, sp)
        elif stem == "keys":
            x = keys_stem(name, sp)
        else:
            x = pattern_stem(name, dict(sp, rt60=sp.get("rt60_p", 1.8), wet=sp.get("wet_p", 0.18)), "pulse")
        out = OUT / f"{name}_{stem}.ogg"
    elif kind == "boss":
        sp = BOSSES[name]
        if stem == "bed":
            # Drone/roar bed fused with the percussion so the boss track stands alone.
            drone_bed = bed_stem(name, sp)
            perc = pattern_stem(name, sp, "bed")
            x = drone_bed * 0.55 + perc
            x = normalize_lufs(x, LUFS["boss_bed"], max_peak_db=-1.5)
        else:
            x = pattern_stem(name, dict(sp, lanes=sp["hi_lanes"]), "hi")
        out = OUT / f"{name}_{stem}.ogg"
    elif kind == "ending":
        x = bed_stem("ending", ENDING) if stem == "bed" else keys_stem("ending", ENDING)
        out = OUT / f"ending_{stem}.ogg"
    else:
        x = STINGERS[name](rng_for("stinger_" + name))
        out = OUT / f"stinger_{name}.ogg"
    if quality <= 0.0:
        # Tonal beds / keys compress well at q2; transient stems and stingers keep q3.
        quality = 2.0 if (kind in ("theme", "ending") and stem in ("bed", "keys")) else 3.0
    encode_ogg(x, out, quality)
    m = measure(x)
    return {"file": out.name, "seconds": round(x.shape[-1] / SR, 2), "lufs": round(m["lufs"], 1),
            "peak": round(m["true_peak"], 1), "kb": round(out.stat().st_size / 1024), "t": round(time.time() - t0, 1)}


def all_tasks() -> list:
    tasks = []
    for name, sp in THEMES.items():
        tasks.append(("theme", name, "bed"))
        tasks.append(("theme", name, "keys"))
        if "lanes" in sp:
            tasks.append(("theme", name, "pulse"))
    for name in BOSSES:
        tasks.append(("boss", name, "bed"))
        tasks.append(("boss", name, "hi"))
    tasks.append(("ending", "ending", "bed"))
    tasks.append(("ending", "ending", "keys"))
    for name in STINGERS:
        tasks.append(("stinger", name, "one"))
    return tasks


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--jobs", type=int, default=8)
    ap.add_argument("--quality", type=float, default=0.0, help="0 = auto (q2 beds/keys, q3 rest)")
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    tasks = [t for t in all_tasks() if args.only in "_".join(t)]
    print(f"{len(tasks)} stems -> {OUT}")
    t0 = time.time()
    with ProcessPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        futs = [pool.submit(build_task, t, args.quality) for t in tasks]
        total_kb = 0
        for t, f in zip(tasks, futs):
            r = f.result()
            total_kb += r["kb"]
            print(f"{r['file']:<34} {r['seconds']:>6}s  {r['lufs']:>6} LUFS  peak {r['peak']:>6}  {r['kb']:>5} KB  ({r['t']}s)")
    print(f"total {total_kb / 1024:.1f} MB in {time.time() - t0:.0f}s")


if __name__ == "__main__":
    main()
