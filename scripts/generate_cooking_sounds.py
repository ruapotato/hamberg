#!/usr/bin/env python3
"""Generate cooking sound effects for the cooking station."""

import numpy as np
import soundfile as sf
from scipy import signal
import os

# Output directory
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), '..', 'audio', 'generated')
SAMPLE_RATE = 44100

def generate_sizzle(duration=3.0):
    """Generate a sizzling/frying sound effect."""
    samples = int(duration * SAMPLE_RATE)
    t = np.linspace(0, duration, samples)

    # Base noise
    noise = np.random.randn(samples)

    # Bandpass filter to get sizzle frequencies (2kHz - 8kHz)
    nyq = SAMPLE_RATE / 2
    low = 2000 / nyq
    high = 8000 / nyq
    b, a = signal.butter(4, [low, high], btype='band')
    sizzle = signal.filtfilt(b, a, noise)

    # Add some crackle pops
    num_pops = int(duration * 15)  # 15 pops per second
    for _ in range(num_pops):
        pop_pos = np.random.randint(0, samples - 500)
        pop_length = np.random.randint(50, 200)
        pop_amp = np.random.uniform(0.3, 0.8)
        decay = np.exp(-np.linspace(0, 5, pop_length))
        pop = np.random.randn(pop_length) * decay * pop_amp
        sizzle[pop_pos:pop_pos + pop_length] += pop

    # Add amplitude modulation for bubbling effect
    bubble_freq = np.random.uniform(3, 8)
    modulation = 0.7 + 0.3 * np.sin(2 * np.pi * bubble_freq * t)
    sizzle *= modulation

    # Fade in/out for looping
    fade_samples = int(0.1 * SAMPLE_RATE)
    fade_in = np.linspace(0, 1, fade_samples)
    fade_out = np.linspace(1, 0, fade_samples)
    sizzle[:fade_samples] *= fade_in
    sizzle[-fade_samples:] *= fade_out

    # Normalize
    sizzle = sizzle / np.max(np.abs(sizzle)) * 0.7

    return sizzle.astype(np.float32)

def generate_cooking_complete():
    """Generate a pleasant completion chime sound."""
    duration = 0.8
    samples = int(duration * SAMPLE_RATE)
    t = np.linspace(0, duration, samples)

    # Two-tone chime (like a success sound)
    freq1 = 880  # A5
    freq2 = 1320  # E6

    # First tone
    tone1_env = np.exp(-t * 4)
    tone1 = np.sin(2 * np.pi * freq1 * t) * tone1_env

    # Second tone (slightly delayed)
    delay_samples = int(0.15 * SAMPLE_RATE)
    tone2_t = np.maximum(t - 0.15, 0)
    tone2_env = np.exp(-tone2_t * 3)
    tone2_env[:delay_samples] = 0
    tone2 = np.sin(2 * np.pi * freq2 * t) * tone2_env

    # Add harmonics for richness
    harmonics1 = np.sin(2 * np.pi * freq1 * 2 * t) * tone1_env * 0.3
    harmonics2 = np.sin(2 * np.pi * freq2 * 2 * t) * tone2_env * 0.3

    chime = tone1 + tone2 + harmonics1 + harmonics2

    # Normalize
    chime = chime / np.max(np.abs(chime)) * 0.8

    return chime.astype(np.float32)

def generate_burn_sound():
    """Generate a burning/hissing sound with a darker tone."""
    duration = 1.2
    samples = int(duration * SAMPLE_RATE)
    t = np.linspace(0, duration, samples)

    # Deep crackling noise
    noise = np.random.randn(samples)

    # Lower frequency bandpass for darker sound
    nyq = SAMPLE_RATE / 2
    low = 500 / nyq
    high = 3000 / nyq
    b, a = signal.butter(3, [low, high], btype='band')
    burn = signal.filtfilt(b, a, noise)

    # Add a descending tone for "uh oh" feeling
    descend_freq = 400 * np.exp(-t * 2)
    descend_tone = np.sin(2 * np.pi * descend_freq * t) * np.exp(-t * 1.5) * 0.4

    # Intense crackle bursts
    num_crackles = 8
    for i in range(num_crackles):
        pos = int(samples * (i / num_crackles) + np.random.randint(-1000, 1000))
        pos = max(0, min(pos, samples - 1000))
        crackle_len = np.random.randint(200, 600)
        crackle_amp = np.random.uniform(0.5, 1.0)
        decay = np.exp(-np.linspace(0, 8, crackle_len))
        crackle = np.random.randn(crackle_len) * decay * crackle_amp
        burn[pos:pos + crackle_len] += crackle

    burn = burn + descend_tone

    # Envelope: quick attack, sustained, then fade
    envelope = np.ones(samples)
    attack = int(0.05 * SAMPLE_RATE)
    release = int(0.3 * SAMPLE_RATE)
    envelope[:attack] = np.linspace(0, 1, attack)
    envelope[-release:] = np.linspace(1, 0, release)
    burn *= envelope

    # Normalize
    burn = burn / np.max(np.abs(burn)) * 0.75

    return burn.astype(np.float32)

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print("Generating cooking sizzle sound...")
    sizzle = generate_sizzle(3.0)
    sf.write(os.path.join(OUTPUT_DIR, 'cooking_sizzle.wav'), sizzle, SAMPLE_RATE)
    print(f"  Saved: cooking_sizzle.wav ({len(sizzle)/SAMPLE_RATE:.1f}s)")

    print("Generating cooking complete sound...")
    complete = generate_cooking_complete()
    sf.write(os.path.join(OUTPUT_DIR, 'cooking_complete.wav'), complete, SAMPLE_RATE)
    print(f"  Saved: cooking_complete.wav ({len(complete)/SAMPLE_RATE:.1f}s)")

    print("Generating burn sound...")
    burn = generate_burn_sound()
    sf.write(os.path.join(OUTPUT_DIR, 'cooking_burn.wav'), burn, SAMPLE_RATE)
    print(f"  Saved: cooking_burn.wav ({len(burn)/SAMPLE_RATE:.1f}s)")

    print("\nAll cooking sounds generated!")

if __name__ == '__main__':
    main()
