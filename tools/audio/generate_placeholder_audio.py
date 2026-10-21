#!/usr/bin/env python3
"""Synthesises the placeholder sounds in assets/audio/ (all made from scratch,
so there is nothing to license). Every file is a stand-in: replace it with a
real recording of the same name, or point data/audio/audio.json elsewhere.

    pip install numpy scipy soundfile
    python3 tools/audio/generate_placeholder_audio.py            # everything
    python3 tools/audio/generate_placeholder_audio.py temple     # just one group (sfx, music, temple, ambience, combat, magic)

Sound effects are short one-shots; music and ambience are seamless loops
(the tail of each loop is folded back onto its start).
"""
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal

SR = 44100
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "audio"
rng = np.random.default_rng(1)


# --------------------------------------------------------------------------
# Building blocks
# --------------------------------------------------------------------------

def t(seconds):
    return np.arange(int(SR * seconds)) / SR


def env(n, attack=0.005, decay=0.2):
    """Exponential decay envelope with a short linear attack."""
    x = np.arange(n) / SR
    e = np.exp(-x / max(decay, 1e-4))
    a = int(attack * SR)
    if a > 0:
        e[:a] *= np.linspace(0, 1, a)
    return e


def noise(seconds, color="white"):
    n = int(SR * seconds)
    w = rng.standard_normal(n)
    if color == "brown":
        w = np.cumsum(w)
        w = signal.detrend(w)
    elif color == "pink":
        b, a = [0.049922035, -0.095993537, 0.050612699, -0.004408786], [1, -2.494956002, 2.017265875, -0.522189400]
        w = signal.lfilter(b, a, w)
    return w / (np.abs(w).max() + 1e-9)


def band(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, hi], btype="bandpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def lowpass(x, hz, order=2):
    return signal.sosfilt(signal.butter(order, hz, btype="lowpass", fs=SR, output="sos"), x)


def highpass(x, hz, order=2):
    return signal.sosfilt(signal.butter(order, hz, btype="highpass", fs=SR, output="sos"), x)


def place(dst, src, at_seconds, gain=1.0):
    i = int(at_seconds * SR)
    j = min(len(dst), i + len(src))
    if i < len(dst):
        dst[i:j] += src[: j - i] * gain


def clink(freq=2400, decay=0.18, seconds=0.4):
    """Small metal impact: a few inharmonic partials."""
    x = t(seconds)
    s = sum(np.sin(2 * np.pi * freq * k * x + rng.uniform(0, 6)) * w
            for k, w in ((1.0, 1.0), (1.61, 0.6), (2.43, 0.4), (3.87, 0.25)))
    return s * env(len(x), 0.001, decay)


def knock(freq=140, seconds=0.25, decay=0.06):
    x = t(seconds)
    body = np.sin(2 * np.pi * freq * x * (1 - 0.3 * x / seconds)) * env(len(x), 0.001, decay)
    click = band(noise(seconds), 800, 4000) * env(len(x), 0.0005, 0.008)
    return body + click * 0.5


def creak(seconds=0.6, f0=160, f1=230):
    """Wood creak: a buzzy, jittery tone through a resonant band."""
    x = t(seconds)
    f = np.linspace(f0, f1, len(x)) * (1 + 0.04 * noise(seconds, "brown"))
    phase = 2 * np.pi * np.cumsum(f) / SR
    saw = signal.sawtooth(phase)
    pulses = (np.sin(phase * 0.5) > 0.6).astype(float)
    s = band(saw * (0.4 + pulses), 300, 2200)
    e = np.sin(np.pi * np.clip(x / seconds, 0, 1)) ** 0.7
    return s * e


def pluck(freq, seconds=2.0, brightness=0.5, decay=0.996):
    """Karplus-Strong plucked string (a lute-ish voice)."""
    n = int(SR * seconds)
    period = int(SR / freq)
    burst = np.zeros(n)
    burst[:period] = lowpass(rng.uniform(-1, 1, period), 1200 + 6000 * brightness, 1)
    # y[n] = x[n] + decay/2 * (y[n-P] + y[n-P-1]): the averaging delay line as one IIR filter.
    a = np.zeros(period + 2)
    a[0] = 1.0
    a[period] = a[period + 1] = -decay * 0.5
    out = signal.lfilter([1.0], a, burst)
    return out * env(n, 0.002, seconds * 0.45)


def normalise(x, peak=0.8):
    return x / (np.abs(x).max() + 1e-9) * peak


def fade(x, a=0.002, b=0.02):
    x = x.copy()
    na, nb = int(a * SR), int(b * SR)
    if na:
        x[:na] *= np.linspace(0, 1, na)
    if nb:
        x[-nb:] *= np.linspace(1, 0, nb)
    return x


def loop_fold(x, length_s):
    """Folds everything past `length_s` back onto the start, for seamless loops."""
    n = int(length_s * SR)
    out = x[:n].copy()
    tail = x[n:]
    out[: len(tail)] += tail[: n]
    return out


def save(rel, x, peak=0.8):
    path = OUT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    data = normalise(x, peak).astype(np.float32)
    # Written in small blocks: libsndfile's Vorbis encoder can crash on long single writes.
    with sf.SoundFile(path, "w", SR, 1, format="OGG", subtype="VORBIS") as f:
        for i in range(0, len(data), 4096):
            f.write(data[i:i + 4096])
    print("wrote", path.relative_to(ROOT), f"{len(x) / SR:.1f}s")


# --------------------------------------------------------------------------
# Sound effects
# --------------------------------------------------------------------------

def sfx():
    x = band(noise(0.04), 1500, 6000) * env(int(0.04 * SR), 0.0005, 0.006)
    x += np.sin(2 * np.pi * 1900 * t(0.04)) * env(int(0.04 * SR), 0.0005, 0.01) * 0.3
    save("sfx/ui_click.ogg", fade(x), 0.5)

    d = 0.28
    x = band(noise(d, "pink"), 400, 3000) * np.sin(np.pi * np.clip(t(d) / d, 0, 1)) ** 2
    save("sfx/ui_open.ogg", fade(x), 0.45)

    d = 0.16
    x = band(noise(d), 1200, 5000) * (0.5 + 0.5 * np.abs(np.sin(2 * np.pi * 28 * t(d)))) * env(int(d * SR), 0.004, 0.06)
    save("sfx/item_pickup.ogg", fade(x), 0.5)

    save("sfx/item_drop.ogg", fade(knock(120, 0.25, 0.05)), 0.6)

    x = np.zeros(int(0.5 * SR))
    place(x, clink(2600, 0.12, 0.4), 0.0)
    place(x, clink(3300, 0.1, 0.4), 0.05, 0.5)
    save("sfx/equip.ogg", fade(x), 0.55)

    x = np.zeros(int(0.6 * SR))
    for k in range(18):
        place(x, clink(rng.uniform(2500, 5000), 0.05, 0.2), rng.uniform(0, 0.35), rng.uniform(0.2, 0.6))
    place(x, knock(90, 0.3, 0.07), 0.0, 0.8)
    save("sfx/equip_armor.ogg", fade(x), 0.6)

    x = np.zeros(int(0.7 * SR))
    for k in range(7):
        place(x, clink(rng.uniform(3800, 5200), 0.09, 0.35), 0.03 + k * 0.06 + rng.uniform(0, 0.03),
              rng.uniform(0.4, 1.0))
    save("sfx/coins.ogg", fade(x), 0.55)

    x = np.zeros(int(0.9 * SR))
    pop = band(noise(0.03), 600, 3000) * env(int(0.03 * SR), 0.0005, 0.006)
    place(x, pop, 0.0)
    for k in range(4):
        d = 0.12
        f = np.linspace(380, 170, int(d * SR))
        b = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * np.clip(t(d) / d, 0, 1))
        place(x, b, 0.2 + k * 0.14, 0.7 - k * 0.1)
    save("sfx/potion.ogg", fade(x), 0.55)

    x = np.zeros(int(0.8 * SR))
    place(x, creak(0.55, 180, 240), 0.0)
    place(x, knock(110, 0.3, 0.05), 0.55, 0.7)
    save("sfx/chest_open.ogg", fade(x), 0.6)

    x = np.zeros(int(1.2 * SR))
    place(x, clink(1800, 0.05, 0.15), 0.0, 0.7)
    place(x, creak(0.9, 140, 200), 0.08)
    save("sfx/door_open.ogg", fade(x), 0.6)

    x = np.zeros(int(0.45 * SR))
    for k in range(3):
        place(x, clink(1400 + k * 60, 0.03, 0.12), k * 0.09)
        place(x, knock(300, 0.1, 0.02), k * 0.09, 0.4)
    save("sfx/locked.ogg", fade(x), 0.55)

    x = np.zeros(int(0.45 * SR))
    place(x, clink(2200, 0.04, 0.15), 0.0)
    place(x, clink(1600, 0.06, 0.2), 0.18)
    place(x, knock(240, 0.12, 0.03), 0.18, 0.5)
    save("sfx/unlock.ogg", fade(x), 0.55)

    d = 1.2
    x = sum(np.sin(2 * np.pi * f * t(d)) * w for f, w in ((660, 1.0), (990, 0.5), (1320, 0.3))) * env(int(d * SR), 0.005, 0.35)
    save("sfx/save.ogg", fade(x), 0.4)

    x = np.zeros(int(0.35 * SR))
    place(x, np.sin(2 * np.pi * 180 * t(0.12)) * env(int(0.12 * SR), 0.003, 0.05), 0.0)
    place(x, np.sin(2 * np.pi * 140 * t(0.15)) * env(int(0.15 * SR), 0.003, 0.06), 0.12)
    save("sfx/error.ogg", fade(x), 0.4)


def combat_sfx():
    """Fight sounds (own random generator, so the other groups stay as they are)."""
    r = np.random.default_rng(11)
    # A blow landing: a dull thump with a short, gritty crunch.
    x = np.zeros(int(0.35 * SR))
    place(x, knock(85, 0.3, 0.06), 0.0)
    crunch = band(noise(0.08), 300, 2400) * env(int(0.08 * SR), 0.001, 0.025)
    place(x, crunch, 0.0, 0.7)
    save("sfx/hit.ogg", fade(x), 0.6)
    # A swing that misses: a whoosh rising through the air.
    d = 0.3
    w = noise(d, "pink")
    sweep = np.zeros_like(w)
    n = len(w)
    for k in range(6):  # band sweep in slices
        a, b = k * n // 6, (k + 1) * n // 6
        sweep[a:b] = band(w, 500 + k * 350, 1500 + k * 500)[a:b]
    x = sweep * np.sin(np.pi * np.clip(t(d) / d, 0, 1)) ** 2
    save("sfx/swing_miss.ogg", fade(x), 0.45)
    # A fight begins: two war-drum beats under a low horn.
    x = np.zeros(int(1.4 * SR))
    for k, at in enumerate((0.0, 0.32)):
        place(x, knock(58, 0.6, 0.12), at, 1.0 - 0.2 * k)
    dh = 1.0
    tt = t(dh)
    horn = sum(np.sin(2 * np.pi * f * tt + 0.3 * np.sin(2 * np.pi * 5 * tt)) * a
               for f, a in ((110, 1.0), (220, 0.5), (330, 0.3), (165, 0.4)))
    horn = lowpass(horn, 1400) * np.minimum(1, tt / 0.15) * np.minimum(1, (dh - tt) / 0.4)
    place(x, horn, 0.3, 0.35 + 0.0 * r.random())
    save("sfx/combat_start.ogg", fade(x), 0.6)


def magic_sfx():
    """Spell sounds (own random generator, so the other groups stay as they are)."""
    r = np.random.default_rng(23)
    # A spell is cast: an airy swell under a shimmer of rising bell partials.
    d = 1.1
    x = np.zeros(int(d * SR))
    air = band(noise(0.9, "pink"), 900, 5000) * np.sin(np.pi * np.clip(t(0.9) / 0.9, 0, 1)) ** 2
    place(x, air, 0.0, 0.35)
    for k, f in enumerate((660, 880, 1100, 1320, 1760)):
        tt = t(0.8)
        glide = f * (1 + 0.06 * tt)  # each partial drifts up a little
        tone = np.sin(2 * np.pi * np.cumsum(glide) / SR) * env(len(tt), 0.01, 0.25)
        place(x, tone, 0.06 * k + r.uniform(0, 0.02), 0.5 - 0.06 * k)
    save("sfx/spell_cast.ogg", fade(x), 0.55)


# --------------------------------------------------------------------------
# Music: plucked-string loops
# --------------------------------------------------------------------------

def note_hz(name):
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    acc = 1 if "#" in name else (-1 if name[1:2] == "b" else 0)
    octave = int(name[-1])
    semis = names[name[0]] + acc + (octave - 4) * 12
    return 440.0 * 2 ** (semis / 12)


def tune(bpm, chords, pattern, bars_per_chord, length_beats, drone_gain=0.12, lead=None):
    beat = 60.0 / bpm
    total = length_beats * beat
    x = np.zeros(int((total + 3.0) * SR))
    b = 0
    for chord in chords:
        for bar in range(bars_per_chord):
            for k, (step, idx) in enumerate(pattern):
                f = note_hz(chord[idx])
                place(x, pluck(f, 2.2, 0.45 + 0.1 * rng.random()), (b * 4 + step) * beat, 0.55 + 0.1 * rng.random())
            # Low drone on the root, re-plucked each bar.
            place(x, pluck(note_hz(chord[0]) / 2, 3.0, 0.2, 0.998), b * 4 * beat, drone_gain * 4)
            b += 1
    if lead:
        for beat_at, name, dur in lead:
            place(x, pluck(note_hz(name), dur * beat + 1.0, 0.7), beat_at * beat, 0.5)
    # A touch of room: short feedback delay.
    d = int(0.23 * SR)
    for _ in range(3):
        x[d:] += x[:-d] * 0.22
    return loop_fold(x, total)


def music():
    chords = [("D3", "A3", "D4", "F4"), ("C3", "G3", "C4", "E4"), ("A#2", "F3", "A#3", "D4"), ("C3", "G3", "C4", "E4")]
    pattern = [(0, 0), (0.5, 1), (1, 2), (1.5, 3), (2, 2), (2.5, 1), (3, 2), (3.5, 3)]
    lead = [(16 + i * 2, n, 1.5) for i, n in enumerate(("A4", "C5", "D5", "A4", "G4", "F4", "E4", "D4"))]
    save("music/village.ogg", tune(84, chords * 2, pattern, 2, 64, lead=lead), 0.7)
    chords = [("A2", "E3", "A3", "C4"), ("F2", "C3", "F3", "A3"), ("G2", "D3", "G3", "B3"), ("E2", "B2", "E3", "G#3")]
    pattern = [(0, 0), (1, 2), (2, 1), (3, 3)]
    save("music/hearth.ogg", tune(66, chords * 2, pattern, 2, 64, drone_gain=0.1), 0.6)


def organ(freqs, seconds, attack=1.4, release=2.0):
    """A soft organ pad: a few sine partials per note, slow swell and fade."""
    n = int(seconds * SR)
    tt = t(seconds)
    x = np.zeros(n)
    for f in freqs:
        for k, a in ((1, 1.0), (2, 0.35), (3, 0.12), (4, 0.06)):
            x += a * np.sin(2 * np.pi * f * k * tt) * (1 + 0.04 * np.sin(2 * np.pi * 4.8 * tt))
    e = np.minimum(1.0, tt / attack) * np.minimum(1.0, np.maximum(0.0, (seconds - tt) / release))
    return x * e / len(freqs)


def temple():
    """Slow modal chords with a plain chant line over them (no randomness, so
    regenerating it on its own leaves the other files unchanged)."""
    chords = [("D3", "A3", "D4", "F4"), ("A#2", "F3", "A#3", "D4"), ("F2", "C3", "F3", "A3"), ("C3", "G3", "C4", "E4")]
    bar = 8.0
    total = bar * len(chords) * 2
    x = np.zeros(int((total + 6.0) * SR))
    for i, chord in enumerate(chords * 2):
        place(x, organ([note_hz(nm) for nm in chord], bar + 2.0), i * bar, 0.5)
    chant = ["A4", "G4", "F4", "G4", "A4", "A4", "D5", "C5", "A4", "G4", "F4", "E4", "D4", "D4", "F4", "E4"]
    for i, nm in enumerate(chant):
        place(x, organ([note_hz(nm)], 3.6, attack=0.5, release=1.2), 16.0 + i * 3.0, 0.22)
    # Stone hall: a few long, darkening echoes.
    for delay, gain in ((0.31, 0.32), (0.53, 0.26), (0.89, 0.2), (1.37, 0.14)):
        d = int(delay * SR)
        x[d:] += lowpass(x[:-d], 2500) * gain
    save("music/temple.ogg", loop_fold(x, total), 0.5)


# --------------------------------------------------------------------------
# Ambience loops
# --------------------------------------------------------------------------

def chirp(seconds=0.12, f0=3200, f1=4600):
    x = t(seconds)
    f = np.linspace(f0, f1, len(x)) + 300 * np.sin(2 * np.pi * 40 * x)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * np.clip(x / seconds, 0, 1)) ** 2


def ambience():
    length = 30.0
    wind = lowpass(noise(length + 2, "brown"), 500) * 0.6
    wind *= 0.6 + 0.4 * np.sin(2 * np.pi * t(length + 2) / 9.0) ** 2
    leaves = band(noise(length + 2, "pink"), 2000, 7000) * 0.05 * (0.5 + 0.5 * np.sin(2 * np.pi * t(length + 2) / 6.5))
    x = wind + leaves
    for k in range(26):
        at = rng.uniform(0, length)
        f0 = rng.uniform(2600, 4200)
        for j in range(rng.integers(2, 6)):
            place(x, chirp(rng.uniform(0.06, 0.14), f0, f0 * rng.uniform(1.1, 1.5)), at + j * rng.uniform(0.1, 0.18),
                  rng.uniform(0.08, 0.2))
    save("ambience/outdoors.ogg", loop_fold(x, length), 0.5)

    rumble = lowpass(noise(length + 2, "brown"), 180) * 0.5
    hiss = band(noise(length + 2, "pink"), 1500, 6000) * 0.04
    x = rumble + hiss
    for k in range(260):
        at = rng.uniform(0, length)
        d = rng.uniform(0.005, 0.03)
        pop = band(noise(d + 0.05), rng.uniform(800, 2000), rng.uniform(3000, 8000)) * env(int((d + 0.05) * SR), 0.0005, d)
        place(x, pop, at, rng.uniform(0.1, 0.6) if rng.random() < 0.9 else 1.0)
    save("ambience/fireplace.ogg", loop_fold(x, length), 0.5)


if __name__ == "__main__":
    import sys
    groups = {"sfx": sfx, "music": music, "temple": temple, "ambience": ambience, "combat": combat_sfx,
              "magic": magic_sfx}
    for name in sys.argv[1:] or list(groups):
        groups[name]()
