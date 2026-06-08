#!/usr/bin/env python3
"""
Procedural audio engine for Mito V3.

Design goals (per direction): low-key, relaxing, RPG vibe, *very* satisfying —
especially the flashcard clicks. Everything is tuned to a C major pentatonic
scale so layered sounds never clash. Soft attacks + gentle reverb tails keep it
calm; crisp transients keep the clicks punchy.

Outputs 16-bit WAV files into MitoV3/Sounds/. SFX are mono; music is stereo.

Run:  python3 tools/gen_audio.py
"""

import math
import os
import struct
import wave

import numpy as np
from scipy.signal import lfilter

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "MitoV3", "Sounds")

# ---------------------------------------------------------------------------
# Note helpers — C major pentatonic palette
# ---------------------------------------------------------------------------

def hz(semitones_from_a4):
    return 440.0 * (2.0 ** (semitones_from_a4 / 12.0))

# Pitch-class semitone offsets relative to A within an octave.
_PC = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}

def N(name):
    """Parse a note name like 'C4', 'F#3', 'Bb2' into a frequency in Hz."""
    pc = _PC[name[0]]
    i = 1
    if len(name) > 1 and name[1] in "#b":
        pc += 1 if name[1] == "#" else -1
        i = 2
    octave = int(name[i:])
    return hz(pc + (octave - 4) * 12)

# ---------------------------------------------------------------------------
# Core synthesis primitives
# ---------------------------------------------------------------------------

def silence(dur):
    return np.zeros(int(dur * SR))

def t_axis(n):
    return np.arange(n) / SR

def env_ad(n, attack, decay, curve=3.0):
    """Attack ramp then exponential-ish decay. Returns length-n envelope."""
    t = t_axis(n)
    a = np.clip(t / max(attack, 1e-5), 0, 1)
    d = np.exp(-np.maximum(t - attack, 0) / max(decay, 1e-5) * curve)
    return a * d

def tone(freq, dur, partials=((1, 1.0),), attack=0.004, decay=0.18,
         curve=3.0, detune=0.0, pitch_drop=0.0):
    """Additive tone. partials = list of (harmonic_mult, amplitude).
    pitch_drop = fraction the pitch glides down over the note (punch)."""
    n = int(dur * SR)
    t = t_axis(n)
    # downward pitch glide for "punch"
    inst_f = freq * (1.0 - pitch_drop * (1 - np.exp(-t / (dur * 0.4 + 1e-6))))
    phase = 2 * np.pi * np.cumsum(inst_f) / SR
    sig = np.zeros(n)
    for mult, amp in partials:
        sig += amp * np.sin(phase * mult + detune * mult)
    sig *= env_ad(n, attack, decay, curve)
    return sig

def noise_burst(dur, lp=4000.0, hp=None, attack=0.001, decay=0.05, curve=3.0):
    """Lowpassed (and optionally highpassed) white-noise transient."""
    n = int(dur * SR)
    x = np.random.uniform(-1, 1, n)
    x = one_pole_lp(x, lp)
    if hp:
        x = x - one_pole_lp(x, hp)
    x *= env_ad(n, attack, decay, curve)
    return x

def one_pole_lp(x, cutoff):
    """Simple one-pole lowpass (vectorised IIR)."""
    a = math.exp(-2 * math.pi * cutoff / SR)
    b = 1 - a
    return lfilter([b], [1, -a], x)

def sweep(f0, f1, dur, attack=0.005, decay=0.2, curve=2.0, wave="sine"):
    """Pitch sweep from f0 to f1 (Hz)."""
    n = int(dur * SR)
    t = t_axis(n)
    inst_f = np.linspace(f0, f1, n)
    phase = 2 * np.pi * np.cumsum(inst_f) / SR
    if wave == "saw":
        sig = 2 * (phase / (2 * np.pi) % 1.0) - 1
    else:
        sig = np.sin(phase)
    sig *= env_ad(n, attack, decay, curve)
    return sig

# ---------------------------------------------------------------------------
# Mixing / mastering helpers
# ---------------------------------------------------------------------------

def pad(sig, dur):
    n = int(dur * SR)
    if len(sig) >= n:
        return sig[:n]
    return np.concatenate([sig, np.zeros(n - len(sig))])

def mix(*sigs):
    n = max(len(s) for s in sigs)
    out = np.zeros(n)
    for s in sigs:
        out[:len(s)] += s
    return out

def at(sig, start, total):
    """Place sig starting at `start` seconds within a buffer of `total` sec."""
    n = int(total * SR)
    out = np.zeros(n)
    s = int(start * SR)
    e = min(n, s + len(sig))
    out[s:e] += sig[:e - s]
    return out

def soft_clip(x, drive=1.0):
    return np.tanh(x * drive)

def normalize(x, peak=0.89):
    m = np.max(np.abs(x)) + 1e-9
    return x / m * peak

def _comb(x, delay, g):
    """Feedback comb: y[i] = x[i] + g*y[i-delay]."""
    a = np.zeros(delay + 1)
    a[0] = 1.0
    a[delay] = -g
    return lfilter([1.0], a, x)

def _allpass(x, delay, g):
    """Schroeder allpass: H(z) = (-g + z^-d) / (1 - g z^-d)."""
    b = np.zeros(delay + 1)
    b[0] = -g
    b[delay] = 1.0
    a = np.zeros(delay + 1)
    a[0] = 1.0
    a[delay] = -g
    return lfilter(b, a, x)

def reverb(x, wet=0.18, room=0.5, decay=0.45):
    """Cheap Schroeder-style reverb: parallel combs + series allpass."""
    combs = [0.0297, 0.0371, 0.0411, 0.0437]
    src = np.concatenate([x, np.zeros(int(SR * 0.6))])
    acc = np.zeros_like(src)
    for d in combs:
        delay = max(1, int(d * SR * (0.7 + room)))
        acc += _comb(src, delay, decay)
    acc /= len(combs)
    acc = _allpass(acc, max(1, int(0.005 * SR)), 0.6)
    dry = np.concatenate([x, np.zeros(len(src) - len(x))])
    return dry * (1 - wet) + acc * wet

def loopify(stereo, xfade=0.4):
    """Crossfade the tail back over the head so the buffer loops seamlessly.
    `stereo` is (n,2); returns trimmed seamless loop."""
    xn = int(xfade * SR)
    head = stereo[:xn].copy()
    tail = stereo[-xn:].copy()
    fade_in = np.linspace(0, 1, xn)[:, None]
    fade_out = np.linspace(1, 0, xn)[:, None]
    stereo[:xn] = head * fade_in + tail * fade_out
    return stereo[:-xn]

def write_wav(name, sig, stereo=False):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    if stereo:
        data = (np.clip(sig, -1, 1) * 32767).astype("<i2")
        frames = data.reshape(-1).tobytes()
        nch = 2
    else:
        data = (np.clip(sig, -1, 1) * 32767).astype("<i2")
        frames = data.tobytes()
        nch = 1
    with wave.open(path, "wb") as w:
        w.setnchannels(nch)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(frames)
    dur = len(sig) / SR
    print(f"  {name:24} {dur:5.2f}s  peak={np.max(np.abs(sig)):.2f}")

# ---------------------------------------------------------------------------
# SOUND DESIGN
# ---------------------------------------------------------------------------

def card_show():
    """The hero click — reveal the answer. Crisp wooden 'tok' + tuned body."""
    click = noise_burst(0.03, lp=6500, hp=1500, attack=0.0005, decay=0.012, curve=4)
    body = tone(N("C5"), 0.18, partials=((1, 1.0), (2, 0.35), (3, 0.12)),
                attack=0.001, decay=0.07, curve=3.5, pitch_drop=0.04)
    glow = tone(N("G5"), 0.14, partials=((1, 0.5),), attack=0.002, decay=0.06)
    s = mix(click * 0.7, body * 0.9, glow * 0.25)
    s = reverb(s, wet=0.12, room=0.3, decay=0.3)
    return normalize(s, 0.92)

def grade_click(note, bright=0.0, soft=0.0):
    """Woody pentatonic tick for a grade button. bright adds sparkle, soft dulls."""
    click = noise_burst(0.02, lp=5000 - soft * 2500, hp=1200,
                        attack=0.0004, decay=0.008, curve=4)
    body = tone(N(note), 0.13, partials=((1, 1.0), (2, 0.3 + bright * 0.3),
                                         (3, 0.08 + bright * 0.2)),
                attack=0.001, decay=0.06, curve=3.5, pitch_drop=0.03)
    layers = [click * 0.45, body * 0.95]
    if bright:
        layers.append(tone(N("E6"), 0.12, partials=((1, 0.4),),
                           attack=0.002, decay=0.05) * bright * 0.4)
    s = mix(*layers)
    s = reverb(s, wet=0.10, room=0.25, decay=0.25)
    return normalize(s, 0.85 + bright * 0.05)

def ui_tap():
    body = tone(N("A4"), 0.09, partials=((1, 1.0), (2, 0.2)), attack=0.001, decay=0.04)
    click = noise_burst(0.012, lp=4500, hp=1500, decay=0.006, curve=4)
    return normalize(mix(body * 0.7, click * 0.3), 0.6)

def ui_back():
    s = sweep(N("E5"), N("C4"), 0.16, attack=0.002, decay=0.08, curve=2.5)
    return normalize(s, 0.55)

def hit(base, drop, dur, noise_lp, body_amp, noise_amp, bright=0.0):
    """Generic impact: sub thump (pitch drops) + lowpassed noise body."""
    thump = tone(base, dur, partials=((1, 1.0), (2, 0.25)),
                 attack=0.0008, decay=dur * 0.5, curve=3, pitch_drop=drop)
    crunch = noise_burst(dur * 0.7, lp=noise_lp, attack=0.0005,
                         decay=dur * 0.25, curve=3)
    layers = [thump * body_amp, crunch * noise_amp]
    if bright:
        layers.append(noise_burst(0.02, lp=9000, hp=3000, decay=0.01, curve=4) * bright)
    s = mix(*layers)
    return s

def hit_basic():
    s = hit(N("A3"), 0.35, 0.16, noise_lp=3500, body_amp=0.8, noise_amp=0.35, bright=0.2)
    s = reverb(s, wet=0.08, room=0.3, decay=0.25)
    return normalize(s, 0.85)

def hit_skill():
    s = hit(N("E3"), 0.4, 0.24, noise_lp=2800, body_amp=0.95, noise_amp=0.45, bright=0.3)
    s = reverb(s, wet=0.10, room=0.35, decay=0.3)
    return normalize(s, 0.9)

def hit_ultimate():
    sub = tone(N("C3") * 0.5, 0.5, partials=((1, 1.0),), attack=0.001,
               decay=0.28, curve=2.5, pitch_drop=0.45)
    boom = hit(N("C3"), 0.5, 0.42, noise_lp=2200, body_amp=1.0, noise_amp=0.55, bright=0.5)
    s = mix(sub * 0.8, boom)
    s = reverb(s, wet=0.16, room=0.6, decay=0.45)
    return normalize(s, 0.95)

def crit():
    """Bright sparkle sting layered over a hit."""
    notes = ["C5", "E5", "G5", "C6"]
    s = silence(0.34)
    for i, nm in enumerate(notes):
        b = tone(N(nm), 0.3, partials=((1, 1.0), (2.01, 0.4), (3, 0.15)),
                 attack=0.001, decay=0.14, curve=3)
        s = mix(s, at(b, i * 0.025, 0.34))
    shimmer = noise_burst(0.18, lp=12000, hp=5000, attack=0.002, decay=0.09, curve=2.5)
    s = mix(s * 0.6, shimmer * 0.3)
    s = reverb(s, wet=0.22, room=0.5, decay=0.4)
    return normalize(s, 0.9)

def enemy_death():
    """Gentle dissolve — downward sweep + airy noise fade (not violent)."""
    sw = sweep(N("A4"), N("A3") * 0.5, 0.5, attack=0.003, decay=0.3, curve=1.8, wave="saw")
    air = noise_burst(0.5, lp=3000, attack=0.01, decay=0.28, curve=1.6)
    poof = tone(N("C4"), 0.4, partials=((1, 0.6), (1.5, 0.2)), attack=0.005,
                decay=0.22, pitch_drop=0.5)
    s = mix(sw * 0.4, air * 0.3, poof * 0.5)
    s = reverb(s, wet=0.2, room=0.5, decay=0.4)
    return normalize(s, 0.8)

def enemy_attack():
    """Darker, duller thud — the enemy hitting the party."""
    s = hit(N("E3") * 0.5, 0.3, 0.2, noise_lp=1800, body_amp=1.0, noise_amp=0.5)
    s = one_pole_lp(s, 2500)
    s = reverb(s, wet=0.08, room=0.3, decay=0.25)
    return normalize(s, 0.7)

def cast_damage():
    """Offensive whoosh + pitched zap — energetic but not harsh."""
    whoosh = sweep(300, 1400, 0.26, attack=0.04, decay=0.14, curve=2, wave="saw")
    whoosh = one_pole_lp(whoosh, 4000)
    zap = tone(N("G4"), 0.22, partials=((1, 1.0), (2, 0.5), (3, 0.25)),
               attack=0.005, decay=0.1, pitch_drop=0.15)
    s = mix(whoosh * 0.4, zap * 0.6)
    s = reverb(s, wet=0.12, room=0.4, decay=0.3)
    return normalize(s, 0.82)

def cast_damage_ult():
    charge = sweep(180, 900, 0.45, attack=0.2, decay=0.2, curve=1.5, wave="saw")
    charge = one_pole_lp(charge, 3500)
    release = mix(
        tone(N("C4"), 0.5, partials=((1, 1.0), (2, 0.5), (3, 0.3), (4, 0.15)),
             attack=0.004, decay=0.25, pitch_drop=0.1),
        sweep(1400, 600, 0.4, attack=0.005, decay=0.22, curve=2),
    )
    s = mix(at(charge, 0, 0.95), at(release * 0.8, 0.4, 0.95))
    s = reverb(s, wet=0.18, room=0.55, decay=0.4)
    return normalize(s, 0.9)

def cast_support():
    """Warm rising bell arpeggio — healing / buff / shield feel."""
    notes = ["C5", "E5", "G5", "C6"]
    total = 0.55
    s = silence(total)
    for i, nm in enumerate(notes):
        bell = tone(N(nm), 0.4, partials=((1, 1.0), (2.0, 0.3), (3.0, 0.12), (4.2, 0.06)),
                    attack=0.006, decay=0.2, curve=2.5)
        s = mix(s, at(bell * (0.9 - i * 0.1), i * 0.06, total))
    pad = tone(N("C4"), total, partials=((1, 0.5), (2, 0.25), (3, 0.12)),
               attack=0.08, decay=0.4, curve=1.5)
    s = mix(s, pad * 0.3)
    s = reverb(s, wet=0.28, room=0.6, decay=0.5)
    return normalize(s, 0.8)

def cast_support_ult():
    notes = ["C5", "E5", "G5", "C6", "E6", "G6"]
    total = 0.9
    s = silence(total)
    for i, nm in enumerate(notes):
        bell = tone(N(nm), 0.6, partials=((1, 1.0), (2, 0.3), (3, 0.12), (4.2, 0.06)),
                    attack=0.006, decay=0.3, curve=2)
        s = mix(s, at(bell * (0.95 - i * 0.08), i * 0.07, total))
    swell = sweep(N("C4"), N("C5"), 0.7, attack=0.3, decay=0.3, curve=1.2)
    s = mix(s, at(swell * 0.3, 0, total))
    s = reverb(s, wet=0.32, room=0.7, decay=0.6)
    return normalize(s, 0.85)

def victory():
    """Pleasant resolving arpeggio + chord — short and warm."""
    seq = [("C5", 0.0), ("E5", 0.12), ("G5", 0.24), ("C6", 0.36)]
    total = 1.7
    s = silence(total)
    for nm, t0 in seq:
        b = tone(N(nm), 0.5, partials=((1, 1.0), (2, 0.3), (3, 0.12)),
                 attack=0.005, decay=0.25, curve=2.5)
        s = mix(s, at(b, t0, total))
    # final major chord
    for nm in ["C5", "E5", "G5", "C6"]:
        b = tone(N(nm), 1.0, partials=((1, 1.0), (2, 0.25), (3, 0.1)),
                 attack=0.01, decay=0.6, curve=1.5)
        s = mix(s, at(b * 0.5, 0.5, total))
    s = reverb(s, wet=0.25, room=0.6, decay=0.55)
    return normalize(s, 0.85)

def defeat():
    seq = [("G4", 0.0), ("E4", 0.18), ("C4", 0.36)]
    total = 1.4
    s = silence(total)
    for nm, t0 in seq:
        b = tone(N(nm), 0.7, partials=((1, 1.0), (2, 0.2)), attack=0.01,
                 decay=0.4, curve=1.8)
        s = mix(s, at(b, t0, total))
    pad = tone(N("C4"), 1.2, partials=((1, 0.5), (1.5, 0.2)), attack=0.1, decay=0.7)
    s = mix(s, at(pad * 0.3, 0.36, total))
    s = reverb(s, wet=0.25, room=0.6, decay=0.5)
    return normalize(s, 0.7)

def reward():
    notes = ["G5", "C6", "E6"]
    total = 0.5
    s = silence(total)
    for i, nm in enumerate(notes):
        b = tone(N(nm), 0.35, partials=((1, 1.0), (2, 0.3)), attack=0.002, decay=0.16)
        s = mix(s, at(b, i * 0.05, total))
    s = reverb(s, wet=0.2, room=0.4, decay=0.35)
    return normalize(s, 0.75)

# ---------------------------------------------------------------------------
# MUSIC — warm lo-fi study, 100% original (commercial-safe, no samples).
#
# Captures a chilled D-minor lo-fi vibe (mellow Rhodes-style chords + pad +
# round bass + a sparse melody). Everything is kept LOW and heavily low-passed,
# with a final master low-pass, so there are no harsh/piercing highs.
# ---------------------------------------------------------------------------

def smooth_env(n, attack, release):
    """Raised-cosine fade in/out for click-free, gradual swells."""
    env = np.ones(n)
    a = min(int(attack * SR), n // 2)
    r = min(int(release * SR), n // 2)
    if a > 0:
        env[:a] = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, a))
    if r > 0:
        env[-r:] = 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, r))
    return env

def warm_pad(freqs, dur, amp=0.5, cutoff=900, detune=0.0):
    """Soft sustained chord bed: lightly detuned sines, heavily low-passed."""
    n = int(dur * SR)
    t = t_axis(n)
    s = np.zeros(n)
    for f in freqs:
        for d in (-0.003, 0.004):
            s += np.sin(2 * np.pi * f * (1 + d + detune * 0.0007) * t)
    s = one_pole_lp(s, cutoff)
    s *= smooth_env(n, attack=0.9, release=1.5)
    return s / len(freqs) * amp

def epiano(freqs, dur, amp=0.45, cutoff=1050):
    """Mellow Rhodes-style block chord with a soft tine attack + gentle tremolo."""
    n = int(dur * SR)
    t = t_axis(n)
    s = np.zeros(n)
    for f in freqs:
        body = np.sin(2 * np.pi * f * t) + 0.26 * np.sin(2 * np.pi * f * 2 * t)
        tine = 0.10 * np.sin(2 * np.pi * f * 3 * t) * np.exp(-t / 0.05)  # soft "bell" attack
        s += body + tine
    s *= 1 - 0.10 * (0.5 - 0.5 * np.cos(2 * np.pi * 4.5 * t))  # Rhodes tremolo
    s = one_pole_lp(s, cutoff)
    s *= env_ad(n, attack=0.012, decay=dur * 0.55, curve=2.0)
    return s / max(len(freqs), 1) * amp

def soft_bass(freq, dur, amp=0.45):
    """Low, round drone — warm body under the chords."""
    n = int(dur * SR)
    t = t_axis(n)
    s = np.sin(2 * np.pi * freq * t) + 0.3 * np.sin(2 * np.pi * freq * 2 * t)
    s = one_pole_lp(s, 480)
    s *= smooth_env(n, attack=0.35, release=0.9)
    return s * amp

def soft_lead(freq, dur, amp=0.26, cutoff=820):
    """A single, slow, mellow melody note with gentle vibrato (kept low)."""
    n = int(dur * SR)
    t = t_axis(n)
    vib = 1 + 0.003 * np.sin(2 * np.pi * 4.5 * t)
    phase = 2 * np.pi * np.cumsum(freq * vib) / SR
    s = np.sin(phase) + 0.18 * np.sin(2 * phase)
    s = one_pole_lp(s, cutoff)
    s *= smooth_env(n, attack=0.3, release=1.1)
    return s * amp

def make_lofi(progression, bpm, bars, melody=None,
              pad_amp=0.4, comp_amp=0.5, bass_amp=0.4, lead_amp=0.24,
              master_cutoff=1500):
    """Layer pad + Rhodes comp + bass + sparse melody into a warm, low loop."""
    beat = 60.0 / bpm
    bar = beat * 4
    total = bar * bars + 1.2
    n = int(total * SR)
    left = np.zeros(n)
    right = np.zeros(n)

    def place(mono, start, pl, pr):
        s = int(start * SR)
        e = min(n, s + len(mono))
        left[s:e] += mono[:e - s] * pl
        right[s:e] += mono[:e - s] * pr

    for b in range(bars):
        chord = progression[b % len(progression)]
        t0 = b * bar
        notes = [N(x) for x in chord["chord"]]
        # sustained pad bed (overlaps into next bar for legato)
        padL = warm_pad(notes, bar * 1.4, amp=pad_amp, cutoff=850, detune=+1)
        padR = warm_pad(notes, bar * 1.4, amp=pad_amp, cutoff=850, detune=-1)
        place(padL, t0, 1.0, 0.25)
        place(padR, t0, 0.25, 1.0)
        # Rhodes comp on beats 1 and 3 only (unhurried half-note feel)
        for bt in (0, 2):
            ch = epiano(notes, beat * 2.2, amp=comp_amp, cutoff=1050)
            place(ch, t0 + bt * beat, 0.85, 0.85)
        # round bass on the downbeat
        bn = soft_bass(N(chord["bass"]), bar * 1.15, amp=bass_amp)
        place(bn, t0, 0.7, 0.7)

    # Sparse melody: (note, start_in_beats, length_in_beats)
    for nm, sb, lb in (melody or []):
        note = soft_lead(N(nm), lb * beat + 1.2, amp=lead_amp)
        pan = 0.5 + 0.15 * math.sin(sb)
        place(note, sb * beat, 1 - pan, pan)

    stereo = np.stack([left, right], axis=1)
    stereo = loopify(stereo, xfade=0.6)
    L = reverb(stereo[:, 0], wet=0.24, room=0.7, decay=0.6)[:len(stereo)]
    R = reverb(stereo[:, 1], wet=0.24, room=0.7, decay=0.6)[:len(stereo)]
    # Final master low-pass — guarantees no piercing highs (ear-friendly).
    L = one_pole_lp(L, master_cutoff)
    R = one_pole_lp(R, master_cutoff)
    out = np.stack([L, R], axis=1)
    out = soft_clip(out, 0.7)
    out = out / (np.max(np.abs(out)) + 1e-9) * 0.6
    return out

def bgm_home():
    # Warm D-minor lo-fi: i - VI - III - VII  (Dm7 - Bbmaj7 - Fmaj7 - C7), slow.
    prog = [
        {"chord": ["D3", "F3", "A3", "C4"],  "bass": "D2"},
        {"chord": ["Bb2", "D3", "F3", "A3"], "bass": "Bb1"},
        {"chord": ["F3", "A3", "C4", "E4"],  "bass": "F2"},
        {"chord": ["C3", "E3", "G3", "Bb3"], "bass": "C2"},
    ]
    melody = [
        ("D4", 3, 3), ("F4", 11, 4), ("C4", 20, 3), ("D4", 27, 4),
    ]
    return make_lofi(prog, bpm=72, bars=8, melody=melody, master_cutoff=1400)

def bgm_battle():
    # Same warm D-minor world, a touch more movement: i - iv - VI - VII.
    prog = [
        {"chord": ["D3", "F3", "A3", "C4"],  "bass": "D2"},
        {"chord": ["G2", "Bb2", "D3", "F3"], "bass": "G1"},
        {"chord": ["Bb2", "D3", "F3", "A3"], "bass": "Bb1"},
        {"chord": ["C3", "E3", "G3", "Bb3"], "bass": "C2"},
    ]
    melody = [
        ("F4", 2, 3), ("E4", 11, 3), ("D4", 19, 3), ("F4", 27, 4),
    ]
    return make_lofi(prog, bpm=76, bars=8, melody=melody, master_cutoff=1500)

# ---------------------------------------------------------------------------

def main():
    np.random.seed(7)
    print("Generating SFX...")
    write_wav("card_show.wav", card_show())
    write_wav("grade_again.wav", grade_click("G3", bright=0.0, soft=1.0))
    write_wav("grade_hard.wav", grade_click("C4", bright=0.0, soft=0.4))
    write_wav("grade_good.wav", grade_click("E4", bright=0.3, soft=0.0))
    write_wav("grade_easy.wav", grade_click("A4", bright=0.7, soft=0.0))
    write_wav("ui_tap.wav", ui_tap())
    write_wav("ui_back.wav", ui_back())
    write_wav("hit_basic.wav", hit_basic())
    write_wav("hit_skill.wav", hit_skill())
    write_wav("hit_ultimate.wav", hit_ultimate())
    write_wav("crit.wav", crit())
    write_wav("enemy_death.wav", enemy_death())
    write_wav("enemy_attack.wav", enemy_attack())
    write_wav("cast_damage.wav", cast_damage())
    write_wav("cast_damage_ult.wav", cast_damage_ult())
    write_wav("cast_support.wav", cast_support())
    write_wav("cast_support_ult.wav", cast_support_ult())
    write_wav("victory.wav", victory())
    write_wav("defeat.wav", defeat())
    write_wav("reward.wav", reward())
    print("Generating music (this takes a moment)...")
    write_wav("bgm_battle.wav", bgm_battle(), stereo=True)
    write_wav("bgm_home.wav", bgm_home(), stereo=True)
    print("Done ->", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
