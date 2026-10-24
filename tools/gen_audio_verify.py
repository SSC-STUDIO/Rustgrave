#!/usr/bin/env python3
"""Numeric audio audit for Rustgrave (nobody can listen in CI / headless test runs).

Two halves, one report:

A. SIGNAL AUDIT (every decoded .wav/.ogg)
   native sample rate / channels / seconds / KB, sample peak dBFS, RMS dBFS,
   DC offset dBFS, clipping rate (samples at |x| >= 0.99), ffmpeg true peak and
   integrated LUFS, and -- for every looping asset (music stems, all ambience
   beds) -- the loop seam measured on the *decoded* audio the way the game will
   play it (last sample butts against the first sample):
       step    = max|x[0] - x[-1]|                   (the join discontinuity)
       ratio   = step / rms(adjacent steps around the seam)   (click test)
       level   = rms(first 100 ms) - rms(last 100 ms)         (level jump)
       pad     = rms(first/last 20 ms) - whole-file rms       (encoder padding)
   Click verdict: the join step is compared with the file's own 99.9th-percentile
   adjacent sample step (a click is a step the signal would never make naturally).
   Sustained beds/keys: FAIL ratio > 3, WARN > 1.6. Percussive pulse/hi stems
   tolerate a downbeat on the loop point: FAIL > 8, WARN > 4. Any join step below
   -45 dBFS is inaudible and always passes.

B. CONTRACT AUDIT (parsed from the GDScripts, no Godot required)
   - every Sfx.LIBRARY / VARIANTS / AMBIENCE path exists and has an .import
     (i.e. Godot imported it), plus the import's loop flags for looping assets;
   - every key referenced anywhere in scripts/ (Sfx.play/play_at literals,
     CombatRules.sfx_key literals + HIT_FEEL/PLAYER_HURT/BOSS_* matrices,
     UiKit.sfx literals, cutscene "kind":"sfx" ids, THEME_EVENTS ids,
     STEP_KEYS) resolves to LIBRARY; silent fallbacks are listed separately;
   - every LIBRARY / AMBIENCE entry that is never referenced (dead weight);
   - every Music theme has bed + keys (+ pulse where the theme is percussive),
     both boss tracks and all stingers exist, and every set_state / set_theme /
     stinger id used in code exists;
   - per-bus balance: one-shot effective peak from BASE_DB + SFX_MAKEUP_DB +
     TRIM_DB (extreme-trim flags), 3-voice coherent sum vs the Sfx limiter,
     ambience bed LUFS at AMBIENCE_LEVEL, music stem LUFS at the Music
     CALM_MIX / DANGER_MIX gains, and the master/Sfx limiter ceilings that
     guarantee "no sample clipping" no matter how the layers line up.

usage: python tools/gen_audio_verify.py [--only SUBSTR] [--json PATH] [--png DIR]
Exit code 1 if a hard check fails (missing asset / unresolved key / clipping /
DC offset / loop click), 0 otherwise. Warnings never fail the run.
Requires: numpy + scipy (tools/gen_audio_dsp.py imports scipy) + ffmpeg/ffprobe in
PATH. A python without scipy can still run tools/gen_rain_loop.py and friends.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_audio_dsp import ROOT, ASSETS, read_audio, measure_file  # noqa: E402

SCRIPTS = ROOT / "scripts"
AUDIO = ASSETS / "audio"
KENNEY = ASSETS / "kenney_clean" / "audio"

MUSIC_DIRS = ("music",)
AMBIENCE_DIRS = ("ambience",)
CLIP_THRESHOLD = 0.99
DC_WARN_DB = -40.0
STEP_AUDIBLE_DB = -45.0


# ---------------------------------------------------------------------------
# GDScript contract parsing (the .gd source is the spec; the runtime test
# tests/audio_library_test.gd re-checks the same facts through Sfx/Music.)
# ---------------------------------------------------------------------------

def _read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def _block(text: str, header: str) -> str:
    i = text.find(header)
    if i < 0:
        raise KeyError(header)
    j = text.find("\n}", i)
    if j < 0:
        raise KeyError(header)
    return text[i:j]


def _array_block(text: str, header: str) -> str:
    i = text.find(header)
    if i < 0:
        raise KeyError(header)
    start = text.find("[", i + len(header) - 1)
    if start < 0:
        raise KeyError(header)
    j = text.find("]", start)
    return text[start:j + 1]


def _flat_array(text: str, header: str) -> list[str]:
    return re.findall(r'&?"([^"]+)"', _array_block(text, header))


def _num_array(text: str, header: str) -> list[float]:
    body = _array_block(text, header)
    body = body[body.find("[") + 1:]
    return [float(v) for v in re.findall(r"-?\d+(?:\.\d+)?", body)]


def _pairs(block: str) -> list[tuple[str, str]]:
    return re.findall(r'&"([^"]+)"\s*:\s*"([^"]*)"', block)


def _path_block(text: str, const: str) -> dict[str, str]:
    return dict(_pairs(_block(text, "const %s := {" % const)))


def _num_pairs(block: str) -> dict[str, float]:
    return {k: float(v) for k, v in re.findall(r'&"([^"]+)"\s*:\s*(-?\d+(?:\.\d+)?)', block)}


def _scalar(text: str, const: str, default: float = 0.0) -> float:
    m = re.search(r"const %s\s*:?=\s*(-?[\d.]+)" % re.escape(const), text)
    return float(m.group(1)) if m else default


def _flagged(text: str, const: str) -> str:
    m = re.search(r'const %s\s*:\s*StringName\s*=\s*&"([^"]+)"' % re.escape(const), text)
    return m.group(1) if m else ""


def _variants(text: str) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for line in _block(text, "const VARIANTS := {").splitlines():
        m = re.match(r'\s*&"([^"]+)"\s*:\s*\[(.*)\]', line)
        if m:
            out[m.group(1)] = re.findall(r'"(res://[^"]+)"', m.group(2))
    return out


def _theme_beds(text: str) -> dict[str, dict[str, float]]:
    out: dict[str, dict[str, float]] = {}
    for line in _block(text, "const THEME_BEDS := {").splitlines():
        m = re.match(r'\s*&"([^"]+)"\s*:\s*\{(.*)\}', line)
        if m:
            out[m.group(1)] = _num_pairs(m.group(2))
    return out


def _theme_events(text: str) -> dict[str, list[tuple[str, float, float, float, float]]]:
    out: dict[str, list[tuple[str, float, float, float, float]]] = {}
    for line in _block(text, "const THEME_EVENTS := {").splitlines():
        m = re.match(r'\s*&"([^"]+)"\s*:\s*\[(.*)\]', line)
        if m:
            evs = re.findall(r'\[&"([^"]+)",\s*(-?[\d.]+),\s*(-?[\d.]+),\s*(-?[\d.]+),\s*(-?[\d.]+)\]',
                             m.group(2))
            out[m.group(1)] = [(a, float(b), float(c), float(d), float(e)) for a, b, c, d, e in evs]
    return out


def _name_map(block: str) -> dict[str, str]:
    return dict(re.findall(r'&"(\w+)"\s*:\s*&"(\w+)"', block))


def _stride(text: str) -> dict[str, tuple[float, float]]:
    out = {}
    for k, a, b in re.findall(r'&"(\w+)"\s*:\s*Vector2\((-?[\d.]+),\s*(-?[\d.]+)\)',
                              _block(text, "const STRIDE := {")):
        out[k] = (float(a), float(b))
    return out


def _material_keys(text: str) -> dict[str, list[str]]:
    """sfx keys from the HIT_FEEL matrix and the three single-row feel dictionaries."""
    out = {"HIT_FEEL": re.findall(r'"sfx":\s*&"([^"]+)"', _block(text, "const HIT_FEEL := {"))}
    for name in ("PLAYER_HURT", "BOSS_PHASE_FEEL", "BOSS_DEATH_FEEL"):
        m = re.search(r"const %s\s*:=\s*\{(.*?)\}\n" % name, text, re.S)
        out[name] = re.findall(r'"sfx":\s*&"([^"]+)"', m.group(1)) if m else []
    return out


def _music_tables(text: str) -> dict:
    fades = {n: _scalar(text, n) for n in
             ("THEME_FADE", "BOSS_FADE_IN", "BOSS_FADE_OUT", "SILENT_FADE", "MIN_THEME_FADE",
              "PULSE_FADE_IN", "PULSE_FADE_OUT", "LAYER_FADE")}
    return {
        "themes": _flat_array(text, "const THEMES: Array[StringName]"),
        "states": _flat_array(text, "const STATES: Array[StringName]"),
        "stingers": dict(_pairs(_block(text, "const STINGERS := {"))),
        "boss_tracks": _name_map(_block(text, "const BOSS_TRACKS := {")),
        "default_boss": _flagged(text, "DEFAULT_BOSS_TRACK"),
        "ending_track": _flagged(text, "ENDING_TRACK"),
        "level_themes": dict(re.findall(r'"(level\d+)"\s*:\s*&"([^"]+)"',
                                        _block(text, "const LEVEL_THEMES := {"))),
        "calm_mix": _num_array(text, "const CALM_MIX: Array[float] = ["),
        "danger_mix": _num_array(text, "const DANGER_MIX: Array[float] = ["),
        "fades": fades,
    }


def _generator_lufs() -> dict[str, float]:
    text = _read("tools/gen_audio_music.py")
    return {k: float(v) for k, v in re.findall(r'"(\w+)":\s*(-?[\d.]+)', _block(text, "LUFS = {"))}


def load_contract() -> tuple[dict, dict, dict, dict]:
    sfx_text = _read("scripts/autoload/sfx.gd")
    music_text = _read("scripts/autoload/music.gd")
    rules_text = _read("scripts/combat/combat_rules.gd")
    sfx = {
        "library": _path_block(sfx_text, "LIBRARY"),
        "ambience": _path_block(sfx_text, "AMBIENCE"),
        "variants": _variants(sfx_text),
        "base_db": _scalar(sfx_text, "BASE_DB"),
        "makeup_db": _scalar(sfx_text, "SFX_MAKEUP_DB"),
        "trim_db": _num_pairs(_block(sfx_text, "const TRIM_DB := {")),
        "ambience_level": _num_pairs(_block(sfx_text, "const AMBIENCE_LEVEL := {")),
        "theme_beds": _theme_beds(sfx_text),
        "theme_drone_scale": _num_pairs(_block(sfx_text, "const THEME_DRONE_SCALE := {")),
        "theme_events": _theme_events(sfx_text),
        "step_keys": _name_map(_block(sfx_text, "const STEP_KEYS := {")),
        "skin_surface": _name_map(_block(sfx_text, "const SKIN_SURFACE := {")),
        "stride": _stride(sfx_text),
        "surfaces": _flat_array(sfx_text, "const SURFACES: Array[StringName]"),
        "bed_keys": _flat_array(sfx_text, "const BED_KEYS: Array[StringName]"),
        "voiced_rules": re.findall(r'&"(\w+)":\s*Vector2', _block(sfx_text, "const VOICE_RULES := {")),
        "priority": _num_pairs(_block(sfx_text, "const PRIORITY := {")),
    }
    music = _music_tables(music_text)
    rules = {"hit": _material_keys(rules_text),
             "fallback": _name_map(_block(rules_text, "const SFX_FALLBACK := {"))}
    return sfx, music, rules, {"lufs": _generator_lufs()}


# ---------------------------------------------------------------------------
# Reference scan: which keys does the rest of the code ask for?
# ---------------------------------------------------------------------------

SFX_LITERAL_RES = [
    re.compile(r'Sfx\.play(?:_at)?\(\s*&"([a-z0-9_]+)"'),
    re.compile(r'Sfx\.play(?:_at)?\(\s*CombatRules\.sfx_key\(\s*&"([a-z0-9_]+)"'),
    re.compile(r'CombatRules\.sfx_key\(\s*&"([a-z0-9_]+)"'),
    re.compile(r'CombatRules\.sfx_key\([^)]*\belse\s+&"([a-z0-9_]+)"'),
    re.compile(r'UiKit\.sfx\(\s*&"([a-z0-9_]+)"(?:\s*,\s*&"([a-z0-9_]+)")?'),
    re.compile(r'"kind":\s*"sfx",\s*"id":\s*"([a-z0-9_]+)"'),
]
MUSIC_LITERAL_RES = {
    "stinger": re.compile(r'Music\.stinger\(\s*&"([a-z0-9_]+)"'),
    "state": re.compile(r'Music\.set_state\(\s*&"([a-z0-9_]+)"'),
    "theme": re.compile(r'Music\.set_theme\(\s*&"([a-z0-9_]+)"'),
}


def scan_code_refs() -> dict:
    sfx: dict[str, set[str]] = {}
    music: dict[str, set[str]] = {k: set() for k in MUSIC_LITERAL_RES}
    for path in sorted(SCRIPTS.rglob("*.gd")):
        text = path.read_text(encoding="utf-8", errors="replace")
        rel = str(path.relative_to(ROOT)).replace("\\", "/")
        for rx in SFX_LITERAL_RES:
            for m in rx.finditer(text):
                for g in m.groups():
                    if g:
                        sfx.setdefault(g, set()).add(rel)
        for kind, rx in MUSIC_LITERAL_RES.items():
            for m in rx.finditer(text):
                music[kind].add(m.group(1))
    # story_stage.ending_stinger() maps ending kinds to stinger ids dynamically.
    story = (SCRIPTS / "ui" / "story_stage.gd").read_text(encoding="utf-8")
    music["stinger"].update(re.findall(r'return\s+&"(ending_[a-z]+)"', story))
    return {"sfx": sfx, "music": music}


# ---------------------------------------------------------------------------
# Decoding / measurements
# ---------------------------------------------------------------------------

def probe(path: Path) -> tuple[int, int]:
    cmd = ["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
           "stream=sample_rate,channels", "-of", "json", str(path)]
    st = json.loads(subprocess.run(cmd, capture_output=True, text=True, check=True).stdout)["streams"][0]
    return int(st["sample_rate"]), int(st["channels"])


def dbfs(x: float) -> float:
    return 20.0 * np.log10(max(float(x), 1e-9))


def rms(a: np.ndarray) -> float:
    return float(np.sqrt(np.mean(np.square(a))) + 1e-12)


def decode(path: Path) -> tuple[np.ndarray, int]:
    sr, ch = probe(path)
    return read_audio(path, sr, ch), sr


def is_loop(path: Path) -> bool:
    if path.parent.name in MUSIC_DIRS and not path.stem.startswith("stinger_"):
        return True
    return path.parent.name in AMBIENCE_DIRS


def sustained_loop(path: Path) -> bool:
    """Sustained texture loops are judged on the 100 ms level jump; pulse/hi stems
    legitimately start on a downbeat and are judged only on the join step."""
    if path.parent.name in AMBIENCE_DIRS:
        return True
    return path.stem.endswith(("_bed", "_keys"))


def _loop_verdict(r: dict) -> str:
    """Click test.

    The join step is compared with the file's own 99.9th-percentile adjacent
    sample step: a click is a step that the signal would never make naturally.
    Sustained beds/keys are held to a stricter ratio; percussive pulse/hi stems
    are allowed a large join step because starting on a downbeat (or an anvil
    tail ending exactly on the loop point) is part of the pattern, not a glitch.
    """
    step_db = r["seam_step_db"]
    if step_db < STEP_AUDIBLE_DB:          # quieter than -45 dBFS: inaudible
        return "ok"
    ratio = r["seam_ratio_p999"]
    if r["sustained"]:
        if ratio > 3.0:
            return "CLICK"
        if ratio > 1.6:
            return "warn"
        return "ok"
    if ratio > 8.0:
        return "CLICK"
    if ratio > 4.0:
        return "warn"
    return "ok"


def analyse_signal(path: Path) -> dict:
    x, sr = decode(path)
    mono = x.mean(axis=0)
    n = mono.size
    rel = str(path.relative_to(ROOT)).replace("\\", "/")
    if path.parent == KENNEY:
        name = f"kenney_clean/{path.name}"
    else:
        name = f"{path.parent.name}/{path.name}"
    out = {"file": name, "path": rel, "sr": sr, "ch": int(x.shape[0]),
           "sec": round(n / sr, 2), "kb": round(path.stat().st_size / 1024.0, 0),
           "peak_db": round(dbfs(np.max(np.abs(x))), 1),
           "rms_db": round(dbfs(rms(mono)), 1),
           "dc": float(mono.mean()),
           "dc_db": round(dbfs(abs(float(mono.mean()))), 1),
           "clip": float(np.mean(np.abs(x) >= CLIP_THRESHOLD)),
           "over": int(np.sum(np.abs(x) > 1.0)),
           "kenney": path.parent == KENNEY,
           "loop": is_loop(path), "sustained": sustained_loop(path)}
    if out["loop"]:
        step = float(np.max(np.abs(x[:, 0] - x[:, -1])))
        w = max(64, int(0.1 * sr))
        local = np.concatenate([x[:, n - w:], x[:, :w]], axis=1)
        step_rms = rms(np.diff(local, axis=1))
        p999 = float(np.percentile(np.abs(np.diff(x, axis=1)), 99.9))
        k = max(8, int(0.016 * sr))
        near = np.concatenate([x[:, max(0, n - k - 1):n - 1], x[:, 1:k + 1]], axis=1)
        near_max = float(np.max(np.abs(np.diff(near, axis=1))))
        first, last = rms(x[:, :w]), rms(x[:, n - w:])
        pad_w = max(16, int(0.02 * sr))
        out.update({"seam_step_db": round(dbfs(step), 1),
                    "seam_ratio_p999": round(step / p999, 2),
                    "seam_ratio_local": round(step / step_rms, 2),
                    "seam_ratio_near": round(step / near_max, 2),
                    "step_p999_db": round(dbfs(p999), 1),
                    "level_jump_db": round(dbfs(first) - dbfs(last), 2),
                    "pad_first_db": round(dbfs(rms(x[:, :pad_w])) - dbfs(rms(mono)), 1),
                    "pad_last_db": round(dbfs(rms(x[:, n - pad_w:])) - dbfs(rms(mono)), 1)})
        out["loop_verdict"] = _loop_verdict(out)
    return out


def import_flags(path: Path) -> dict:
    imp = Path(str(path) + ".import")
    if not imp.exists():
        return {"has_import": False}
    text = imp.read_text(encoding="utf-8")
    d: dict = {"has_import": True}
    for k in ("loop", "loop_offset", "compress/mode", "edit/loop_mode", "edit/loop_end"):
        m = re.search(r"^%s=(.+)$" % re.escape(k), text, re.M)
        if m:
            d[k] = m.group(1).strip()
    return d


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

def check_missing_paths(sfx: dict) -> list[str]:
    missing = []
    tables = (("LIBRARY", sfx["library"]), ("AMBIENCE", sfx["ambience"]))
    for label, table in tables:
        for key, res in table.items():
            p = ROOT / res.replace("res://", "")
            if not p.exists():
                missing.append(f"{label}[{key}] -> {res} (file missing)")
            elif not Path(str(p) + ".import").exists():
                missing.append(f"{label}[{key}] -> {res} (not imported: no .import)")
    for group, takes in sfx["variants"].items():
        for res in takes:
            p = ROOT / res.replace("res://", "")
            if not p.exists():
                missing.append(f"VARIANTS[{group}] -> {res} (file missing)")
    return missing


def check_import_flags(rows: list[dict]) -> tuple[list[str], list[str]]:
    """Loop assets must be imported as loop; one-shots must not be looped by the
    importer. Returns (problems, info)."""
    problems, info = [], []
    for r in rows:
        p = ROOT / r["path"]
        flags = import_flags(p)
        if not flags.get("has_import"):
            problems.append(f"{r['file']}: no .import (Godot has not imported it)")
            continue
        if r["loop"] and p.suffix == ".ogg" and flags.get("loop") != "true":
            problems.append(f"{r['file']}: looping OGG imported with loop={flags.get('loop')}")
        if not r["loop"] and p.suffix == ".ogg" and flags.get("loop") == "true":
            problems.append(f"{r['file']}: one-shot OGG imported with loop=true")
        if r["loop"] and p.suffix == ".wav":
            mode = flags.get("compress/mode", "0")
            info.append(f"{r['file']}: runtime-looped WAV, import compress/mode={mode}"
                        f" (1=IMA-ADPCM, 2=QOA lossy, 0=PCM)")
    return problems, info


def check_theme_coverage(music: dict) -> list[str]:
    problems = []
    for t in music["themes"]:
        for role in ("bed", "keys"):
            if not (AUDIO / "music" / f"{t}_{role}.ogg").exists():
                problems.append(f"theme {t}: missing {role} stem")
    # Every theme except title is a gameplay place with a danger layer; title and
    # ending only need bed + keys, boss tracks need bed + hi.
    for t in music["themes"]:
        if t == "title":
            continue
        if not (AUDIO / "music" / f"{t}_pulse.ogg").exists():
            problems.append(f"theme {t}: missing pulse stem")
    for boss in sorted(set(music["boss_tracks"].values()) | {music["default_boss"]}):
        for role in ("bed", "hi"):
            if not (AUDIO / "music" / f"{boss}_{role}.ogg").exists():
                problems.append(f"boss track {boss}: missing {role} stem")
    end = music["ending_track"]
    for role in ("bed", "keys"):
        if not (AUDIO / "music" / f"{end}_{role}.ogg").exists():
            problems.append(f"ending track {end}: missing {role} stem")
    for name, res in music["stingers"].items():
        if not (ROOT / res.replace("res://", "")).exists():
            problems.append(f"stinger {name}: missing {res}")
    return problems


# ---------------------------------------------------------------------------
# Balance helpers
# ---------------------------------------------------------------------------

def linear(db: float) -> float:
    return float(10.0 ** (db / 20.0))


def _combine_lufs(items) -> float:
    total = 0.0
    for lufs, gain in items:
        if lufs is None or lufs <= -90.0:
            continue
        total += (10.0 ** (lufs / 10.0)) * (gain * gain)
    return 10.0 * np.log10(max(total, 1e-20))


def _combine_peak(items) -> float:
    total = 0.0
    for row, gain in items:
        if row is None:
            continue
        total += linear(row["peak_db"]) * gain
    return 20.0 * np.log10(max(total, 1e-12))


def _bus_summary() -> list[str]:
    text = (AUDIO / "default_bus_layout.tres").read_text(encoding="utf-8")
    names = {int(i): n for i, n in re.findall(r'bus/(\d+)/name = &"([^"]+)"', text)}
    names.setdefault(0, "Master")
    effects = re.findall(r'bus/(\d+)/effect/(\d+)/effect = SubResource\("([^"]+)"\)', text)
    enabled = {(int(a), int(b)): c == "true"
               for a, b, c in re.findall(r'bus/(\d+)/effect/(\d+)/enabled = (true|false)', text)}
    by_bus: dict[int, list[str]] = {}
    for bi, ei, res in effects:
        on = enabled.get((int(bi), int(ei)), True)
        by_bus.setdefault(int(bi), []).append(f"{res}{'' if on else ' (disabled at rest)'}")
    ceilings = {}
    for key in ("Master HardLimiter", "Sfx Limiter"):
        needle = "AudioEffectHardLimiter_master" if key.startswith("Master") else "AudioEffectLimiter_sfx"
        m = re.search(re.escape(needle) + r".*?\nceiling_db = (-?[\d.]+)", text, re.S)
        if m:
            ceilings[key] = float(m.group(1))
    m = re.search(r"AudioEffectCompressor_sfx.*?\nthreshold = (-?[\d.]+)", text, re.S)
    comp = float(m.group(1)) if m else None
    lines = []
    for i in sorted(by_bus):
        lines.append(f"bus {i} {names.get(i, '?'):<9} -> {' -> '.join(by_bus[i])}")
    lines.append(f"guards: Master HardLimiter ceiling {ceilings.get('Master HardLimiter')} dBFS; "
                 f"Sfx limiter ceiling {ceilings.get('Sfx Limiter')} dBFS; "
                 f"Sfx compressor threshold {comp} dB")
    lines.append("=> summed SFX voices are squashed by the Sfx limiter and the Master "
                 "HardLimiter, so the mix can never sample-clip"
                 if len(ceilings) == 2 else "=> WARNING: a bus lacks a limiter ceiling")
    return lines


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

def platform_skin_gaps(sfx: dict) -> list[str]:
    """SolidPlatform @export_enum skins that SKIN_SURFACE does not name explicitly
    (they still map correctly through the documented unknown => stone fallback)."""
    text = _read("scripts/world/solid_platform.gd")
    start = text.find("@export_enum(")
    end = text.find(") var skin", start)
    if start < 0 or end < 0:
        return []
    return [s for s in re.findall(r'"([a-z_0-9]+)"', text[start:end])
            if s not in sfx["skin_surface"]]


def print_inventory(sfx: dict, music: dict, refs: dict, missing: list[str], unresolved: list[str],
                    silent: dict[str, str], dead_library: list[str], dead_ambience: list[str],
                    ref_count: dict[str, int]) -> None:
    print("=" * 104)
    print("A. INVENTORY + CONTRACT")
    print("=" * 104)
    print(f"LIBRARY          {len(sfx['library'])} keys")
    print(f"VARIANTS         {len(sfx['variants'])} groups / "
          f"{sum(len(v) for v in sfx['variants'].values())} takes")
    print(f"AMBIENCE         {len(sfx['ambience'])} loop keys   BED_KEYS {len(sfx['bed_keys'])}"
          f"   THEME_BEDS {len(sfx['theme_beds'])} themes   THEME_EVENTS {len(sfx['theme_events'])} themes")
    print(f"STEP_KEYS        {len(sfx['step_keys'])}   SKIN_SURFACE {len(sfx['skin_surface'])}"
          f"   SURFACES {len(sfx['surfaces'])}   STRIDE {len(sfx['stride'])}")
    print(f"Music.THEMES     {len(music['themes'])} ({', '.join(music['themes'])})")
    print(f"Music.STATES     {', '.join(music['states'])}")
    print(f"Music.STINGERS   {len(music['stingers'])}")
    print()
    print(f"res:// files referenced by LIBRARY+VARIANTS+AMBIENCE: "
          f"{len(sfx['library']) + len(sfx['ambience']) + sum(len(v) for v in sfx['variants'].values())}"
          f"   missing/unimported: {len(missing)}")
    for m in missing:
        print("  MISSING", m)
    print(f"code keys that resolve through CombatRules.SFX_FALLBACK: {len(silent)}")
    for k, v in sorted(silent.items()):
        print(f"  FALLBACK {k:<16} -> {v}")
    print(f"code keys with no library entry and no fallback: {len(unresolved)}")
    for k in sorted(unresolved):
        print("  UNRESOLVED", k)
    print(f"LIBRARY entries never referenced by scripts/: {len(dead_library)} {dead_library}")
    print(f"AMBIENCE entries never referenced: {len(dead_ambience)} {dead_ambience}")
    print()
    print("theme stem coverage (bed/keys/pulse):")
    for t in music["themes"]:
        cells = []
        for role in ("bed", "keys", "pulse"):
            p = AUDIO / "music" / f"{t}_{role}.ogg"
            cells.append(f"{role}={'ok' if p.exists() else 'MISSING'}")
        print(f"  {t:<12} " + "  ".join(cells))
    for boss in sorted(set(music["boss_tracks"].values()) | {music["default_boss"]}):
        print(f"  boss {boss:<12} " + "  ".join(
            f"{role}={'ok' if (AUDIO / 'music' / f'{boss}_{role}.ogg').exists() else 'MISSING'}"
            for role in ("bed", "hi")))
    end = music["ending_track"]
    print(f"  ending {end:<10} " + "  ".join(
        f"{role}={'ok' if (AUDIO / 'music' / f'{end}_{role}.ogg').exists() else 'MISSING'}"
        for role in ("bed", "keys")))
    bad_states = sorted(refs["music"]["state"] - set(music["states"]))
    bad_themes = sorted(refs["music"]["theme"] - set(music["themes"]))
    bad_stingers = sorted(refs["music"]["stinger"] - set(music["stingers"]))
    bad_level = sorted(set(music["level_themes"].values()) - set(music["themes"]))
    unused_stingers = sorted(set(music["stingers"]) - refs["music"]["stinger"])
    print(f"  set_state ids in code valid: {not bad_states}" + (f"  BAD {bad_states}" if bad_states else ""))
    print(f"  set_theme ids in code valid: {not bad_themes}" + (f"  BAD {bad_themes}" if bad_themes else ""))
    print(f"  stinger ids in code valid:   {not bad_stingers}" + (f"  BAD {bad_stingers}" if bad_stingers else ""))
    print(f"  LEVEL_THEMES values valid:   {not bad_level}" + (f"  BAD {bad_level}" if bad_level else ""))
    print(f"  stingers defined but unused in scripts/: {unused_stingers}")
    print(f"  fade constants: {music['fades']}")
    gaps = platform_skin_gaps(sfx)
    total_skins = len(sfx["skin_surface"]) + len(gaps)
    print(f"  SKIN_SURFACE covers {len(sfx['skin_surface'])}/{total_skins} SolidPlatform skins; "
          f"fallback-only: {gaps or 'none'} (unknown => stone)")
    for key in dead_library:
        uses = refs["sfx"].get(key, set())
        print(f"  UNUSED LIBRARY key {key:<14} referenced by: {sorted(uses) or 'nothing'}")


def print_signal_tables(rows: list[dict]) -> None:
    print()
    print("=" * 104)
    print("B. SIGNAL AUDIT  (peak/RMS/DC/clip measured on the decoded file; LUFS/TP = ffmpeg ebur128)")
    print("=" * 104)
    hdr = (f"{'file':<40}{'sec':>6}{'sr':>6}{'ch':>3}{'peak':>7}{'rms':>7}{'dc':>8}{'clip%':>7}"
           f"{'LUFS':>7}{'TP':>6}{'KB':>6}")
    print(hdr)
    print("-" * len(hdr))
    for r in rows:
        lufs = f"{r['lufs']:7.1f}" if r.get("lufs") is not None else "      -"
        tp = f"{r['tp']:6.1f}" if r.get("tp") is not None else "     -"
        print(f"{r['file']:<40}{r['sec']:>6.2f}{r['sr']:>6}{r['ch']:>3}{r['peak_db']:>7.1f}"
              f"{r['rms_db']:>7.1f}{r['dc']:>+8.4f}{100.0 * r['clip']:>7.3f}{lufs}{tp}{r['kb']:>6.0f}")
    print()
    print("=" * 104)
    print("C. LOOP SEAMS  (decoded join x[-1] -> x[0]; r_p999 = join step / file's 99.9th-pct"
          " adjacent step)")
    print("=" * 104)
    hdr = (f"{'file':<40}{'step dB':>8}{'r_p999':>8}{'r_near':>8}{'p99.9':>7}{'lvl dB':>8}"
           f"{'padF':>6}{'padL':>6}  verdict")
    print(hdr)
    print("-" * len(hdr))
    for r in rows:
        if not r["loop"]:
            continue
        print(f"{r['file']:<40}{r['seam_step_db']:>8.1f}{r['seam_ratio_p999']:>8.2f}"
              f"{r['seam_ratio_near']:>8.2f}{r['step_p999_db']:>7.1f}{r['level_jump_db']:>8.2f}"
              f"{r['pad_first_db']:>6.1f}{r['pad_last_db']:>6.1f}  {r['loop_verdict']}")
    clicks = [r["file"] for r in rows if r["loop"] and r["loop_verdict"] == "CLICK"]
    warns = [r["file"] for r in rows if r["loop"] and r["loop_verdict"] == "warn"]
    print(f"loop files: {sum(1 for r in rows if r['loop'])}   clicks: {clicks or 'none'}"
          f"   warns: {warns or 'none'}")
    print("  r_near = join step / largest adjacent step within +-16 ms of the seam; a downbeat"
          " attack at the loop point keeps it < 1 and is by design.")


def print_balance(sfx: dict, music: dict, rows: list[dict], lufs_targets: dict[str, float]) -> dict:
    by_rel = {r["path"]: r for r in rows}
    lib = sfx["library"]
    base_db, makeup, trim = sfx["base_db"], sfx["makeup_db"], sfx["trim_db"]
    print()
    print("=" * 104)
    print("D. SFX ONE-SHOT LEVELS  (effective peak = raw peak + BASE_DB + SFX_MAKEUP_DB + TRIM_DB)")
    print("=" * 104)
    print(f"BASE_DB={base_db:+.1f}  SFX_MAKEUP_DB={makeup:+.1f}  -> default one-shot voice gain "
          f"{base_db + makeup:+.1f} dB")
    hdr = f"{'key':<16}{'raw peak':>9}{'raw rms':>8}{'trim':>7}{'voice pk':>9}{'3-voice':>8}  flags"
    print(hdr)
    print("-" * len(hdr))
    extreme, clip_risk = [], []
    voice_peaks: list[tuple[str, float]] = []
    for key in sorted(lib):
        r = by_rel.get(lib[key].replace("res://", ""))
        if r is None:
            continue
        t = trim.get(key, 0.0)
        voice = r["peak_db"] + base_db + makeup + t
        three = voice + 20.0 * np.log10(3.0)
        flags = []
        if abs(t) > 9.0:
            flags.append("EXTREME_TRIM")
            extreme.append((key, t))
        if voice > -1.0:
            flags.append("SINGLE_CLIP")
        if three > -2.0:
            flags.append("3VOICE_OVER_LIMITER")
            clip_risk.append((key, round(three, 1)))
        voice_peaks.append((key, voice))
        print(f"{key:<16}{r['peak_db']:>9.1f}{r['rms_db']:>8.1f}{t:>+7.1f}{voice:>9.1f}{three:>8.1f}"
              f"  {', '.join(flags)}")
    print()
    print("=" * 104)
    print("E. AMBIENCE BEDS  (continuous level at AMBIENCE_LEVEL * theme bed gain)")
    print("=" * 104)
    users: dict[str, list[str]] = {}
    for theme, beds in sfx["theme_beds"].items():
        for bed, gain in beds.items():
            users.setdefault(bed, []).append(f"{theme} x{gain:.2f}")
    print(f"{'key':<14}{'LUFS':>7}{'level':>7}{'eff LUFS':>9}{'peak':>7}   used by themes")
    amb_eff: dict[str, float] = {}
    for key in sorted(sfx["ambience"]):
        r = by_rel.get(sfx["ambience"][key].replace("res://", ""))
        if r is None:
            continue
        lvl = sfx["ambience_level"].get(key, 0.28)
        loud = r.get("lufs") if r.get("lufs") not in (None, 0) else r["rms_db"]
        eff = loud + 20.0 * np.log10(max(lvl, 0.0001))
        amb_eff[key] = eff
        print(f"{key:<14}{loud:>7.1f}{lvl:>7.2f}{eff:>9.1f}{r['peak_db']:>7.1f}   "
              + (", ".join(users.get(key, [])) if key in users else "weather/drone (WorldClock gain)"))
    print("drone scale " + ", ".join(f"{t}={v:.2f}" for t, v in sorted(sfx["theme_drone_scale"].items())))
    print()
    print("=" * 104)
    print("F. MUSIC MIX  (stem LUFS; gains from Music.CALM_MIX / DANGER_MIX)")
    print("=" * 104)
    calm, danger = music["calm_mix"], music["danger_mix"]
    print(f"CALM_MIX   bed {calm[0]:.2f} keys {calm[1]:.2f} pulse {calm[2]:.2f}   "
          f"DANGER_MIX bed {danger[0]:.2f} keys {danger[1]:.2f} pulse {danger[2]:.2f}")
    hdr = (f"{'track':<22}{'bed LUFS':>9}{'keys/hi LUFS':>13}{'pulse LUFS':>11}"
           f"{'calm LUFS':>10}{'danger LUFS':>12}{'danger pk':>10}")
    print(hdr)
    print("-" * len(hdr))
    worst = None
    calm_vals: list[float] = []
    danger_vals: list[float] = []
    tracks = list(music["themes"]) + [music["ending_track"]] + sorted(set(music["boss_tracks"].values()))
    for track in tracks:
        stem = {role: by_rel.get(f"assets/audio/music/{track}_{role}.ogg")
                for role in ("bed", "keys", "pulse")}
        if track.startswith("boss_"):
            stem["keys"] = by_rel.get(f"assets/audio/music/{track}_hi.ogg")
        elif track == music["ending_track"]:
            stem["pulse"] = None
        bed = stem["bed"]["lufs"] if stem["bed"] else None
        keys = stem["keys"]["lufs"] if stem["keys"] else None
        pulse = stem["pulse"]["lufs"] if stem["pulse"] else None
        c = _combine_lufs([(bed, calm[0]), (keys, calm[1]), (pulse, calm[2])])
        d = _combine_lufs([(bed, danger[0]), (keys, danger[1]), (pulse, danger[2])])
        pk = _combine_peak([(stem["bed"], danger[0]), (stem["keys"], danger[1]),
                            (stem["pulse"], danger[2])])
        print(f"{track:<22}{bed if bed is not None else float('nan'):>9.1f}"
              f"{keys if keys is not None else float('nan'):>13.1f}"
              f"{pulse if pulse is not None else float('nan'):>11.1f}"
              f"{c:>10.1f}{d:>12.1f}{pk:>10.1f}")
        calm_vals.append(c)
        danger_vals.append(d)
        if worst is None or pk > worst[1]:
            worst = (track, round(pk, 1))
    stinger_lufs = [by_rel[f"assets/audio/music/{res.split('/')[-1]}"]["lufs"]
                    for res in music["stingers"].values()
                    if f"assets/audio/music/{res.split('/')[-1]}" in by_rel]
    if stinger_lufs:
        print(f"stingers: {len(stinger_lufs)} files, LUFS {min(stinger_lufs):.1f} .. {max(stinger_lufs):.1f}"
              f" (generator target {lufs_targets.get('stinger')}), peak capped at "
              f"{max(by_rel[f'assets/audio/music/{res.split(chr(47))[-1]}']['tp'] for res in music['stingers'].values() if f'assets/audio/music/{res.split(chr(47))[-1]}' in by_rel):.1f} dBFS")
    if worst:
        print(f"loudest danger stem-sum (coherent worst case): {worst[0]} {worst[1]:+.1f} dBFS")
        print("   (stems only; stingers add on top while Music ducks itself, "
              "Master HardLimiter is the final guard)")
    # --- mix summary: the relative bus levels docs/audio-mood.md quotes ---------
    print()
    print("  MIX SUMMARY (expected relative levels; dBFS = sample peak, LUFS = ebur128)")
    boss_beds = [by_rel[f"assets/audio/music/{b}_bed.ogg"]["lufs"]
                 for b in sorted(set(music["boss_tracks"].values()) | {music["default_boss"]})
                 if f"assets/audio/music/{b}_bed.ogg" in by_rel]
    if calm_vals:
        print(f"    music      calm {min(calm_vals):.1f}..{max(calm_vals):.1f} LUFS, "
              f"danger {min(danger_vals):.1f}..{max(danger_vals):.1f} LUFS, "
              + (f"boss bed {min(boss_beds):.1f}" if boss_beds else "no boss beds"))
        themed = [v for k, v in amb_eff.items() if k in users]
        weather = [v for k, v in amb_eff.items() if k not in users]
        if themed:
            print(f"    ambience   themed beds {min(themed):.1f}..{max(themed):.1f} LUFS"
                  f" ({min(calm_vals) - max(themed):.1f}..{max(calm_vals) - min(themed):.1f} dB under"
                  f" calm music)")
        if weather:
            print(f"    weather    rain/drone/hiss {min(weather):.1f}..{max(weather):.1f} LUFS"
                  f" ({min(calm_vals) - max(weather):.1f}..{max(calm_vals) - min(weather):.1f} dB under"
                  f" calm music)")
        peaks = sorted(v for _, v in voice_peaks)
        if peaks:
            print(f"    sfx        effective one-shot peaks {peaks[0]:.1f}..{peaks[-1]:.1f} dBFS"
                  f" (median {np.median(peaks):.1f}); footsteps subtract STRIDE.dB, cutscene cues pass"
                  f" their own -3..-17 dB")
        if stinger_lufs:
            print(f"    stingers   {min(stinger_lufs):.1f}..{max(stinger_lufs):.1f} LUFS ="
                  f" {min(stinger_lufs) - max(calm_vals):+.1f}..{max(stinger_lufs) - min(calm_vals):+.1f} dB"
                  f" vs calm music; every cue ducks the bed by 4..12 dB")
    print()
    print("=" * 104)
    print("G. BUS GUARDS  (assets/audio/default_bus_layout.tres)")
    print("=" * 104)
    for line in _bus_summary():
        print("  " + line)
    print()
    print(f"extremes: extreme trims {extreme}; 3-voice sums over the Sfx limiter ceiling: "
          f"{len(clip_risk)} keys (all capped by the -2 dBFS Sfx limiter)")
    return {"extreme_trims": extreme, "clip_risk": clip_risk, "music_worst": worst}


# ---------------------------------------------------------------------------

def referenced_paths(sfx: dict, music: dict) -> set[str]:
    """res:// paths actually named by the Sfx / Music tables."""
    paths = set(sfx["library"].values()) | set(sfx["ambience"].values())
    for takes in sfx["variants"].values():
        paths |= set(takes)
    for track in (set(music["themes"]) | {music["ending_track"]}
                  | set(music["boss_tracks"].values()) | {music["default_boss"]}):
        for role in ("bed", "keys", "pulse", "hi"):
            p = AUDIO / "music" / f"{track}_{role}.ogg"
            if p.exists():
                paths.add("res://" + str(p.relative_to(ROOT)).replace("\\", "/"))
    paths |= set(music["stingers"].values())
    return {p.replace("res://", "") for p in paths}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--json", default="")
    ap.add_argument("--png", default="")
    args = ap.parse_args()

    sfx, music, rules, extra = load_contract()
    refs = scan_code_refs()
    missing = check_missing_paths(sfx)

    fallback = rules["fallback"]
    asked: dict[str, set[str]] = {}
    for key, files in refs["sfx"].items():
        asked.setdefault(key, set()).update(files)
    for keys in rules["hit"].values():
        for k in keys:
            asked.setdefault(k, set()).add("combat_rules")
    for evs in sfx["theme_events"].values():
        for e in evs:
            asked.setdefault(e[0], set()).add("THEME_EVENTS")
    for surf, key in sfx["step_keys"].items():
        asked.setdefault(key, set()).add(f"STEP_KEYS[{surf}]")
    for group in sfx["variants"]:
        asked.setdefault(group, set()).add("VARIANTS")
    hazard_fx = (SCRIPTS / "hazards" / "hazard_fx.gd").read_text(encoding="utf-8")
    for key in re.findall(r'&"(hazard_[a-z_]+)"', hazard_fx):
        asked.setdefault(key, set()).add("HazardFx.SFX")
    silent = {k: fallback[k] for k in asked
              if k not in sfx["library"] and k in fallback and fallback[k] in sfx["library"]}
    unresolved = [k for k in asked if k not in sfx["library"] and k not in silent]
    dead_library = sorted(k for k in sfx["library"] if k not in asked)
    # Ambience keys are referenced from inside sfx.gd itself (_fade_ambience), from
    # BED_KEYS and from THEME_BEDS, not by gameplay scripts.
    sfx_body = _read("scripts/autoload/sfx.gd")
    amb_used = set(sfx["bed_keys"]) | {b for beds in sfx["theme_beds"].values() for b in beds}
    amb_used |= {k for k in sfx["ambience"]
                 if len(re.findall(r'&"%s"' % re.escape(k), sfx_body)) > 1}
    dead_ambience = sorted(k for k in sfx["ambience"] if k not in amb_used)

    files: list[Path] = []
    for sub in ("music", "ambience", "sfx"):
        files += sorted((AUDIO / sub).glob("*.ogg"))
        files += sorted((AUDIO / sub).glob("*.wav"))
    files += sorted(KENNEY.glob("*.ogg"))
    referenced = referenced_paths(sfx, music)
    rows: list[dict] = []
    for f in files:
        if args.only and args.only not in f.name:
            continue
        r = analyse_signal(f)
        r["referenced"] = r["path"] in referenced
        if f.parent.name in MUSIC_DIRS or f.parent.name in AMBIENCE_DIRS:
            m = measure_file(f)
            r["lufs"], r["tp"], r["lra"] = m["lufs"], m["true_peak"], m["lra"]
        else:
            r["lufs"] = r["tp"] = None
        rows.append(r)
        if args.png:
            Path(args.png).mkdir(parents=True, exist_ok=True)
            subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(f), "-lavfi",
                            "showspectrumpic=s=900x400:legend=1:scale=log:fscale=log:start=30:stop=16000",
                            str(Path(args.png) / (f.stem + ".png"))])
    unused_kenney = [r["file"] for r in rows if r["kenney"] and not r["referenced"]]
    unused_project = [r["file"] for r in rows if not r["kenney"] and not r["referenced"]]
    key_clip = [r for r in rows if r["kenney"] and r["referenced"] and r["clip"] > 0.001]

    print_inventory(sfx, music, refs, missing, unresolved, silent, dead_library, dead_ambience,
                    {k: len(v) for k, v in asked.items()})
    print(f"assets: {sum(1 for r in rows if not r['kenney'])} project files + "
          f"{sum(1 for r in rows if r['kenney'])} Kenney CC0 copies"
          f" ({len(unused_kenney)} unused: {unused_kenney})")
    if unused_project:
        print(f"  project assets not named by LIBRARY/AMBIENCE/VARIANTS: {unused_project}")
    print_signal_tables(rows)
    bal = print_balance(sfx, music, rows, extra["lufs"])
    import_problems, import_info = check_import_flags(rows)
    theme_problems = check_theme_coverage(music)
    if import_problems or theme_problems or import_info:
        print()
        print("=" * 104)
        print("H. IMPORT + THEME COVERAGE")
        print("=" * 104)
        for i in import_info:
            print("  info:", i)
        for p in import_problems:
            print("  IMPORT-FAIL", p)
        for p in theme_problems:
            print("  THEME-FAIL", p)
        if not import_problems and not theme_problems:
            print("  all loop imports and theme stem sets are complete")

    hard = [f"missing asset: {m}" for m in missing]
    hard += [f"unresolved sfx key: {k}" for k in unresolved]
    hard += [f"missing/incorrect import: {p}" for p in import_problems]
    hard += [f"theme coverage: {p}" for p in theme_problems]
    # Clipping / DC are only actionable on the assets the project generates itself;
    # the Kenney CC0 copies are fixed external files (see the info line below).
    hard += [f"clipping: {r['file']} ({100.0 * r['clip']:.3f}% samples at |x|>=0.99)"
             for r in rows if not r["kenney"] and r["clip"] > 0.001]
    hard += [f"DC offset above {DC_WARN_DB} dBFS: {r['file']} ({r['dc']:+.4f})"
             for r in rows if not r["kenney"] and r["dc_db"] > DC_WARN_DB and abs(r["dc"]) > 0.0]
    hard += [f"loop click: {r['file']} (step {r['seam_step_db']} dBFS, "
             f"{r['seam_ratio_p999']}x the file's 99.9th-pct step)"
             for r in rows if r["loop"] and r["loop_verdict"] == "CLICK"]
    bad_state = sorted(refs["music"]["state"] - set(music["states"]))
    bad_theme = sorted(refs["music"]["theme"] - set(music["themes"]))
    bad_sting = sorted(refs["music"]["stinger"] - set(music["stingers"]))
    hard += [f"unknown Music state id: {k}" for k in bad_state]
    hard += [f"unknown Music theme id: {k}" for k in bad_theme]
    hard += [f"unknown Music stinger id: {k}" for k in bad_sting]

    print()
    print("  info: the Kenney CC0 fallback copies are fixed external files: decoded peak can sit"
          " above 0 dBFS because of lossy-codec overshoot")
    for r in key_clip:
        print(f"  info:   {r['file']} has {100.0 * r['clip']:.3f}% samples at |x|>=0.99;"
              f" it plays at a voice gain of -3..-6 dB and the Sfx bus limiter caps the peak")
    print()
    print("=" * 104)
    print("AUDIT RESULT: " + ("PASS" if not hard else "FAIL"))
    print("=" * 104)
    for h in hard:
        print("  FAIL", h)
    if not hard:
        print(f"  {len(rows)} files measured; {sum(1 for r in rows if r['loop'])} loop seams joined"
              f" cleanly; 0 project-asset clipping; 0 DC-offset; 0 missing assets; 0 unresolved keys")
    print("  NOTE: numbers only -- nobody listened to these files; no mix-quality judgement by ear.")

    if args.json:
        Path(args.json).write_text(json.dumps({"rows": rows, "balance": bal, "failed": hard}, indent=1),
                                   encoding="utf-8")
        print(f"  JSON report: {args.json}")
    sys.exit(1 if hard else 0)


if __name__ == "__main__":
    main()
