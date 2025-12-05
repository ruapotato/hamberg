#!/usr/bin/env python3
"""Generate snow footstep sound effect."""

import numpy as np
import soundfile as sf
from scipy import signal
import os

# Output directory
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), '..', 'audio', 'generated')
SAMPLE_RATE = 44100

def generate_snow_footstep(duration=0.25):
    """Generate a crunchy snow footstep sound.

    Snow footsteps have a distinctive soft crunch with high-frequency content
    from ice crystals compressing.
    """
    samples = int(duration * SAMPLE_RATE)
    t = np.linspace(0, duration, samples)

    # Base noise - pink noise for snow
    noise = np.random.randn(samples)

    # Pink noise filter (1/f spectrum) - softer than white noise
    # Create simple 1/f filter
    freqs = np.fft.rfftfreq(samples, 1/SAMPLE_RATE)
    freqs[0] = 1  # Avoid division by zero
    pink_filter = 1 / np.sqrt(freqs)
    pink_filter[0] = 0  # DC component

    noise_fft = np.fft.rfft(noise)
    pink_noise = np.fft.irfft(noise_fft * pink_filter, samples)

    # Bandpass to get snowy crunch (500Hz - 4kHz)
    nyq = SAMPLE_RATE / 2
    low = 500 / nyq
    high = 4000 / nyq
    b, a = signal.butter(3, [low, high], btype='band')
    crunch = signal.filtfilt(b, a, pink_noise)

    # Add high-frequency crystal sounds (8kHz - 12kHz)
    high_low = 6000 / nyq
    high_high = 12000 / nyq
    b2, a2 = signal.butter(2, [high_low, high_high], btype='band')
    crystals = signal.filtfilt(b2, a2, noise) * 0.15

    # Combine
    sound = crunch + crystals

    # Add some micro-crunches (small amplitude variations)
    num_crunches = int(duration * 40)  # 40 per second
    for _ in range(num_crunches):
        crunch_pos = np.random.randint(0, max(1, samples - 200))
        crunch_length = np.random.randint(30, 100)
        crunch_amp = np.random.uniform(0.1, 0.4)
        decay = np.exp(-np.linspace(0, 4, crunch_length))
        micro_crunch = np.random.randn(crunch_length) * decay * crunch_amp
        end_pos = min(crunch_pos + crunch_length, samples)
        actual_length = end_pos - crunch_pos
        sound[crunch_pos:end_pos] += micro_crunch[:actual_length]

    # Envelope - quick attack, medium decay (foot pressing into snow)
    attack_time = 0.02
    decay_time = duration - attack_time
    attack_samples = int(attack_time * SAMPLE_RATE)
    decay_samples = samples - attack_samples

    envelope = np.ones(samples)
    envelope[:attack_samples] = np.linspace(0, 1, attack_samples) ** 0.5  # Quick attack
    envelope[attack_samples:] = np.exp(-np.linspace(0, 3, decay_samples))  # Exponential decay

    sound *= envelope

    # Normalize
    max_val = np.max(np.abs(sound))
    if max_val > 0:
        sound = sound / max_val * 0.7

    return sound.astype(np.float32)

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Generate snow footstep
    print("Generating footstep_snow.wav...")
    sound = generate_snow_footstep(0.25)
    output_path = os.path.join(OUTPUT_DIR, 'footstep_snow.wav')
    sf.write(output_path, sound, SAMPLE_RATE)
    print(f"  Saved to {output_path}")

    print("\nDone!")

if __name__ == '__main__':
    main()
