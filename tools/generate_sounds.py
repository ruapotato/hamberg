#!/usr/bin/env python3
"""Generate game sound effects using only Python stdlib (wave, struct, math, random).

Outputs 44100 Hz, 16-bit mono WAV files to audio/generated/.
"""

import math
import os
import random
import struct
import wave

SAMPLE_RATE = 44100
MAX_AMP = 32767
OUTPUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "audio", "generated")


def ensure_output_dir():
    os.makedirs(OUTPUT_DIR, exist_ok=True)


def write_wav(filename: str, samples: list[float]):
    """Write normalized float samples (-1.0 to 1.0) as 16-bit mono WAV."""
    filepath = os.path.join(OUTPUT_DIR, filename)
    # Clamp samples
    clamped = [max(-1.0, min(1.0, s)) for s in samples]
    raw = b"".join(struct.pack("<h", int(s * MAX_AMP)) for s in clamped)

    with wave.open(filepath, "w") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(raw)
    print(f"  Written: {filepath} ({len(samples)} samples, {len(samples)/SAMPLE_RATE:.3f}s)")


def white_noise(n: int) -> list[float]:
    """Generate n samples of white noise."""
    return [random.uniform(-1.0, 1.0) for _ in range(n)]


def sine_wave(freq: float, n: int, phase: float = 0.0) -> list[float]:
    """Generate n samples of a sine wave at given frequency."""
    return [math.sin(2.0 * math.pi * freq * i / SAMPLE_RATE + phase) for i in range(n)]


def bandpass_simple(samples: list[float], low_freq: float, high_freq: float) -> list[float]:
    """Simple bandpass filter using running average subtraction.

    Not a proper DSP filter, but good enough for sound effects.
    Uses two simple RC low-pass filters to create a bandpass.
    """
    # Low-pass at high_freq
    rc_high = 1.0 / (2.0 * math.pi * high_freq)
    dt = 1.0 / SAMPLE_RATE
    alpha_high = dt / (rc_high + dt)

    lp_high = [0.0] * len(samples)
    lp_high[0] = samples[0] * alpha_high
    for i in range(1, len(samples)):
        lp_high[i] = lp_high[i-1] + alpha_high * (samples[i] - lp_high[i-1])

    # Low-pass at low_freq
    rc_low = 1.0 / (2.0 * math.pi * low_freq)
    alpha_low = dt / (rc_low + dt)

    lp_low = [0.0] * len(samples)
    lp_low[0] = lp_high[0] * alpha_low
    for i in range(1, len(samples)):
        lp_low[i] = lp_low[i-1] + alpha_low * (lp_high[i] - lp_low[i-1])

    # Bandpass = high_lp - low_lp
    return [lp_high[i] - lp_low[i] for i in range(len(samples))]


def apply_envelope(samples: list[float], fade_in_ms: float, sustain_ms: float, fade_out_ms: float) -> list[float]:
    """Apply attack-sustain-release envelope."""
    result = list(samples)
    n = len(result)
    fade_in_samples = int(fade_in_ms * SAMPLE_RATE / 1000)
    sustain_samples = int(sustain_ms * SAMPLE_RATE / 1000)
    fade_out_samples = int(fade_out_ms * SAMPLE_RATE / 1000)

    for i in range(n):
        if i < fade_in_samples:
            # Fade in
            result[i] *= i / max(1, fade_in_samples)
        elif i < fade_in_samples + sustain_samples:
            # Sustain (full volume)
            pass
        else:
            # Fade out
            fade_pos = i - fade_in_samples - sustain_samples
            if fade_out_samples > 0:
                t = 1.0 - fade_pos / fade_out_samples
                t = max(0.0, t)
                # Exponential fade for natural decay
                result[i] *= t * t
            else:
                result[i] = 0.0
    return result


def mix(a: list[float], b: list[float], b_vol: float = 1.0) -> list[float]:
    """Mix two sample arrays, padding shorter one with zeros."""
    length = max(len(a), len(b))
    result = [0.0] * length
    for i in range(length):
        va = a[i] if i < len(a) else 0.0
        vb = (b[i] if i < len(b) else 0.0) * b_vol
        result[i] = va + vb
    return result


def normalize(samples: list[float], target: float = 0.9) -> list[float]:
    """Normalize samples to target peak amplitude."""
    peak = max(abs(s) for s in samples) if samples else 1.0
    if peak < 0.001:
        return samples
    scale = target / peak
    return [s * scale for s in samples]


# =============================================================================
# Sound generators
# =============================================================================

def generate_sword_swing():
    """Pure whoosh — no tonal ding, just air cutting."""
    print("Generating sword_swing.wav...")
    total_ms = 180
    n = int(total_ms * SAMPLE_RATE / 1000)

    noise = white_noise(n)
    filtered = bandpass_simple(noise, 600, 3000)
    shaped = apply_envelope(filtered, fade_in_ms=3, sustain_ms=30, fade_out_ms=147)

    write_wav("sword_swing.wav", normalize(shaped, 0.5))


def generate_punch_swing():
    """Lighter, shorter whoosh."""
    print("Generating punch_swing.wav...")
    total_ms = 150
    n = int(total_ms * SAMPLE_RATE / 1000)

    noise = white_noise(n)
    filtered = bandpass_simple(noise, 1000, 3000)
    shaped = apply_envelope(filtered, fade_in_ms=3, sustain_ms=30, fade_out_ms=117)

    write_wav("punch_swing.wav", normalize(shaped, 0.5))


def generate_sword_hit():
    """Satisfying thwack - sharp transient + low resonance."""
    print("Generating sword_hit.wav...")

    # Sharp transient (noise burst)
    transient_ms = 5
    transient_n = int(transient_ms * SAMPLE_RATE / 1000)
    transient = white_noise(transient_n)
    transient = apply_envelope(transient, 0.5, 2, 2.5)

    # Low resonance body
    body_ms = 150
    body_n = int(body_ms * SAMPLE_RATE / 1000)
    # Mix a few low frequencies for richness
    body = sine_wave(100, body_n)
    body2 = sine_wave(150, body_n)
    body3 = sine_wave(80, body_n)
    body_mixed = mix(mix(body, body2, 0.6), body3, 0.3)
    body_shaped = apply_envelope(body_mixed, 1, 20, 129)

    # Mid crack
    crack_n = int(30 * SAMPLE_RATE / 1000)
    crack = white_noise(crack_n)
    crack = bandpass_simple(crack, 500, 2000)
    crack = apply_envelope(crack, 0.5, 5, 24.5)

    combined = mix(mix(transient, body_shaped, 0.7), crack, 0.5)
    write_wav("sword_hit.wav", normalize(combined, 0.85))


def generate_punch_hit():
    """Meaty thud - low thump + short noise crack."""
    print("Generating punch_hit.wav...")

    # Low frequency thump
    thump_ms = 80
    thump_n = int(thump_ms * SAMPLE_RATE / 1000)
    thump = sine_wave(80, thump_n)
    thump2 = sine_wave(60, thump_n)
    thump_mixed = mix(thump, thump2, 0.5)
    thump_shaped = apply_envelope(thump_mixed, 1, 15, 64)

    # Short noise crack
    crack_ms = 15
    crack_n = int(crack_ms * SAMPLE_RATE / 1000)
    crack = white_noise(crack_n)
    crack = bandpass_simple(crack, 200, 1500)
    crack = apply_envelope(crack, 0.3, 3, 11.7)

    combined = mix(thump_shaped, crack, 0.6)
    write_wav("punch_hit.wav", normalize(combined, 0.75))


def generate_tree_chop():
    """Wood chopping - sharp crack + wood resonance."""
    print("Generating tree_chop.wav...")

    total_ms = 200

    # Sharp initial crack
    crack_ms = 8
    crack_n = int(crack_ms * SAMPLE_RATE / 1000)
    crack = white_noise(crack_n)
    crack = apply_envelope(crack, 0.3, 3, 4.7)

    # Wood resonance (200-400 Hz range)
    body_ms = 200
    body_n = int(body_ms * SAMPLE_RATE / 1000)
    body = sine_wave(280, body_n)
    body2 = sine_wave(350, body_n)
    body3 = sine_wave(220, body_n)
    body_mixed = mix(mix(body, body2, 0.5), body3, 0.3)
    body_shaped = apply_envelope(body_mixed, 1, 30, 169)

    # High-frequency wood splintering
    splinter_ms = 40
    splinter_n = int(splinter_ms * SAMPLE_RATE / 1000)
    splinter = white_noise(splinter_n)
    splinter = bandpass_simple(splinter, 1500, 4000)
    splinter = apply_envelope(splinter, 0.5, 10, 29.5)

    combined = mix(mix(crack, body_shaped, 0.6), splinter, 0.3)
    write_wav("tree_chop.wav", normalize(combined, 0.8))


def generate_bush_break():
    """Light rustling break - filtered noise with leafy quality."""
    print("Generating bush_break.wav...")

    total_ms = 180
    n = int(total_ms * SAMPLE_RATE / 1000)

    # High-frequency rustling noise (leafy)
    noise = white_noise(n)
    filtered = bandpass_simple(noise, 2000, 6000)
    shaped = apply_envelope(filtered, 2, 40, 138)

    # Lower rustling layer
    noise2 = white_noise(n)
    filtered2 = bandpass_simple(noise2, 800, 2500)
    shaped2 = apply_envelope(filtered2, 3, 30, 147)

    # Subtle snap
    snap_ms = 5
    snap_n = int(snap_ms * SAMPLE_RATE / 1000)
    snap = white_noise(snap_n)
    snap = apply_envelope(snap, 0.2, 2, 2.8)

    combined = mix(mix(shaped, shaped2, 0.5), snap, 0.3)
    write_wav("bush_break.wav", normalize(combined, 0.6))


def main():
    print("=== Hamberg Sound Generator ===")
    ensure_output_dir()

    generate_sword_swing()
    generate_punch_swing()
    generate_sword_hit()
    generate_punch_hit()
    generate_tree_chop()
    generate_bush_break()

    print("\nDone! Generated 6 sound effects.")


if __name__ == "__main__":
    main()
