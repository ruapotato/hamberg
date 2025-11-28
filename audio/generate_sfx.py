#!/usr/bin/env python3
"""
Procedural Sound Effect Generator for Hamberg
Generates high-quality .wav files using synthesis techniques.

Usage:
    python generate_sfx.py              # Generate all sounds
    python generate_sfx.py --list       # List available sounds
    python generate_sfx.py sword_hit    # Generate specific sound
"""

import numpy as np
from scipy import signal
from scipy.ndimage import uniform_filter1d
import soundfile as sf
import os
import argparse
from pathlib import Path

# Audio settings
SAMPLE_RATE = 44100
OUTPUT_DIR = Path(__file__).parent / "generated"


def ensure_output_dir():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


def normalize(audio, peak=0.9):
    """Normalize audio to peak amplitude."""
    max_val = np.max(np.abs(audio))
    if max_val > 0:
        return audio * (peak / max_val)
    return audio


def fade(audio, fade_in_ms=5, fade_out_ms=50):
    """Apply fade in/out to prevent clicks."""
    fade_in_samples = int(SAMPLE_RATE * fade_in_ms / 1000)
    fade_out_samples = int(SAMPLE_RATE * fade_out_ms / 1000)

    if fade_in_samples > 0 and fade_in_samples < len(audio):
        audio[:fade_in_samples] *= np.linspace(0, 1, fade_in_samples)
    if fade_out_samples > 0 and fade_out_samples < len(audio):
        audio[-fade_out_samples:] *= np.linspace(1, 0, fade_out_samples)

    return audio


def save_wav(audio, filename):
    """Save audio to wav file."""
    ensure_output_dir()
    filepath = OUTPUT_DIR / f"{filename}.wav"
    sf.write(filepath, audio, SAMPLE_RATE)
    print(f"  Generated: {filepath}")


def lowpass(audio, cutoff_hz, order=4):
    """Apply lowpass filter."""
    nyq = SAMPLE_RATE / 2
    normalized_cutoff = min(cutoff_hz / nyq, 0.99)
    b, a = signal.butter(order, normalized_cutoff, btype='low')
    return signal.filtfilt(b, a, audio)


def highpass(audio, cutoff_hz, order=4):
    """Apply highpass filter."""
    nyq = SAMPLE_RATE / 2
    normalized_cutoff = min(cutoff_hz / nyq, 0.99)
    b, a = signal.butter(order, normalized_cutoff, btype='high')
    return signal.filtfilt(b, a, audio)


def bandpass(audio, low_hz, high_hz, order=4):
    """Apply bandpass filter."""
    nyq = SAMPLE_RATE / 2
    low = min(low_hz / nyq, 0.99)
    high = min(high_hz / nyq, 0.99)
    if low >= high:
        low = high * 0.5
    b, a = signal.butter(order, [low, high], btype='band')
    return signal.filtfilt(b, a, audio)


def distortion(audio, amount=2.0):
    """Apply soft clipping distortion."""
    return np.tanh(audio * amount)


def bitcrush(audio, bits=8):
    """Reduce bit depth for lo-fi effect."""
    levels = 2 ** bits
    return np.round(audio * levels) / levels


def reverb_simple(audio, decay=0.3, delay_ms=30):
    """Simple comb filter reverb."""
    delay_samples = int(SAMPLE_RATE * delay_ms / 1000)
    output = audio.copy()
    for i in range(delay_samples, len(audio)):
        output[i] += output[i - delay_samples] * decay
    return output


def pitch_envelope(duration_s, start_hz, end_hz):
    """Generate frequency envelope."""
    samples = int(SAMPLE_RATE * duration_s)
    return np.linspace(start_hz, end_hz, samples)


def amplitude_envelope(duration_s, attack=0.01, decay=0.1, sustain=0.5, release=0.2):
    """Generate ADSR envelope."""
    samples = int(SAMPLE_RATE * duration_s)
    total = attack + decay + release

    attack_samples = int(samples * attack / total)
    decay_samples = int(samples * decay / total)
    release_samples = samples - attack_samples - decay_samples

    env = np.concatenate([
        np.linspace(0, 1, max(1, attack_samples)),
        np.linspace(1, sustain, max(1, decay_samples)),
        np.linspace(sustain, 0, max(1, release_samples))
    ])

    return env[:samples] if len(env) >= samples else np.pad(env, (0, samples - len(env)))


def noise(duration_s, color='white'):
    """Generate noise."""
    samples = int(SAMPLE_RATE * duration_s)
    white = np.random.randn(samples)

    if color == 'white':
        return white
    elif color == 'pink':
        # Pink noise: -3dB per octave
        freqs = np.fft.rfftfreq(samples, 1/SAMPLE_RATE)
        freqs[0] = 1  # Avoid division by zero
        pink_filter = 1 / np.sqrt(freqs)
        spectrum = np.fft.rfft(white) * pink_filter
        return np.fft.irfft(spectrum, samples)
    elif color == 'brown':
        # Brown noise: -6dB per octave (integrated white noise)
        return np.cumsum(white) / 100

    return white


def sine_wave(freq_hz, duration_s, phase=0):
    """Generate sine wave."""
    t = np.linspace(0, duration_s, int(SAMPLE_RATE * duration_s), endpoint=False)
    return np.sin(2 * np.pi * freq_hz * t + phase)


def fm_synthesis(carrier_hz, mod_hz, mod_index, duration_s):
    """FM synthesis for complex timbres."""
    t = np.linspace(0, duration_s, int(SAMPLE_RATE * duration_s), endpoint=False)
    modulator = mod_index * np.sin(2 * np.pi * mod_hz * t)
    return np.sin(2 * np.pi * carrier_hz * t + modulator)


# =============================================================================
# COMBAT SOUNDS
# =============================================================================

def gen_sword_hit():
    """Melee weapon hitting enemy - sharp metallic impact with body thud."""
    duration = 0.25

    # Metallic ring (high frequency sine with fast decay)
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))
    ring = np.sin(2 * np.pi * 1200 * t) * np.exp(-t * 25)
    ring += np.sin(2 * np.pi * 2400 * t) * np.exp(-t * 35) * 0.5
    ring += np.sin(2 * np.pi * 800 * t) * np.exp(-t * 20) * 0.3

    # Impact thud (noise burst)
    impact = noise(duration, 'brown') * np.exp(-t * 30)
    impact = lowpass(impact, 400)

    # Combine
    audio = ring * 0.4 + impact * 0.6
    audio = fade(normalize(audio), fade_in_ms=1, fade_out_ms=30)
    save_wav(audio, "sword_hit")


def gen_sword_swing():
    """Sword whoosh through air."""
    duration = 0.3
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Filtered noise with pitch sweep
    swoosh = noise(duration, 'pink')

    # Bandpass that sweeps in frequency
    center_freq = 800 + 1200 * (1 - np.exp(-t * 8))

    # Apply time-varying filter by chunking
    chunk_size = 512
    filtered = np.zeros_like(swoosh)
    for i in range(0, len(swoosh) - chunk_size, chunk_size):
        freq = center_freq[i]
        chunk = swoosh[i:i+chunk_size]
        filtered[i:i+chunk_size] = bandpass(chunk, freq * 0.5, freq * 1.5)

    # Amplitude envelope - builds then fades
    env = np.sin(np.pi * t / duration) ** 0.5
    audio = filtered * env

    audio = fade(normalize(audio), fade_in_ms=10, fade_out_ms=50)
    save_wav(audio, "sword_swing")


def gen_parry():
    """Successful parry - sharp metallic clang."""
    duration = 0.4
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Multiple metallic frequencies (inharmonic for bell-like quality)
    freqs = [523, 784, 1046, 1318, 1568]  # C5 and harmonics with slight detuning
    audio = np.zeros_like(t)

    for i, freq in enumerate(freqs):
        decay = 8 + i * 2
        audio += np.sin(2 * np.pi * freq * t) * np.exp(-t * decay) * (1 / (i + 1))

    # Add click at start
    click = noise(0.01, 'white')
    click = highpass(click, 2000)
    audio[:len(click)] += click * 2

    # Slight reverb
    audio = reverb_simple(audio, decay=0.15, delay_ms=15)

    audio = fade(normalize(audio), fade_in_ms=0, fade_out_ms=80)
    save_wav(audio, "parry")


def gen_player_hurt():
    """Player taking damage - grunt with impact."""
    duration = 0.35
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Low impact thud
    impact = noise(duration, 'brown')
    impact = lowpass(impact, 200) * np.exp(-t * 15)

    # Grunt-like FM sound
    grunt = fm_synthesis(120, 80, 3, duration)
    grunt *= np.exp(-t * 8)
    grunt = lowpass(grunt, 500)

    audio = impact * 0.5 + grunt * 0.5
    audio = fade(normalize(audio), fade_in_ms=2, fade_out_ms=50)
    save_wav(audio, "player_hurt")


def gen_enemy_hurt():
    """Enemy taking damage."""
    duration = 0.2
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Higher pitched grunt
    grunt = fm_synthesis(200, 120, 4, duration)
    grunt *= np.exp(-t * 12)
    grunt = lowpass(grunt, 800)

    # Impact
    impact = noise(duration, 'brown')
    impact = lowpass(impact, 300) * np.exp(-t * 25)

    audio = impact * 0.4 + grunt * 0.6
    audio = fade(normalize(audio), fade_in_ms=1, fade_out_ms=30)
    save_wav(audio, "enemy_hurt")


def gen_enemy_death():
    """Enemy dying - extended grunt and thud."""
    duration = 0.6
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Descending grunt
    freq_env = 180 * np.exp(-t * 3)
    grunt = np.sin(2 * np.pi * np.cumsum(freq_env) / SAMPLE_RATE)
    grunt *= np.exp(-t * 4)
    grunt = lowpass(grunt, 600)

    # Body fall thud
    fall_start = int(0.2 * SAMPLE_RATE)
    fall = np.zeros_like(t)
    fall_noise = noise(0.3, 'brown')
    fall_noise = lowpass(fall_noise, 150)
    fall_env = np.exp(-np.linspace(0, 1, len(fall_noise)) * 8)
    fall[fall_start:fall_start + len(fall_noise)] = fall_noise * fall_env

    audio = grunt * 0.5 + fall * 0.5
    audio = fade(normalize(audio), fade_in_ms=2, fade_out_ms=100)
    save_wav(audio, "enemy_death")


def gen_critical_hit():
    """Extra powerful hit - emphasized version of sword_hit."""
    duration = 0.35
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Stronger metallic ring
    ring = np.sin(2 * np.pi * 800 * t) * np.exp(-t * 15)
    ring += np.sin(2 * np.pi * 1600 * t) * np.exp(-t * 20) * 0.6
    ring += np.sin(2 * np.pi * 400 * t) * np.exp(-t * 10) * 0.4

    # Heavy impact
    impact = noise(duration, 'brown') * np.exp(-t * 20)
    impact = lowpass(impact, 300)

    # Add bass boom
    boom = sine_wave(60, duration) * np.exp(-t * 12)

    audio = ring * 0.3 + impact * 0.4 + boom * 0.3
    audio = distortion(audio, 1.5)
    audio = fade(normalize(audio), fade_in_ms=1, fade_out_ms=60)
    save_wav(audio, "critical_hit")


# =============================================================================
# MOVEMENT SOUNDS
# =============================================================================

def gen_footstep_dirt():
    """Footstep on dirt/grass."""
    duration = 0.15
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Crunchy noise
    step = noise(duration, 'pink')
    step = bandpass(step, 200, 2000)
    step *= np.exp(-t * 30)

    # Low thud
    thud = noise(duration, 'brown')
    thud = lowpass(thud, 150)
    thud *= np.exp(-t * 40)

    audio = step * 0.6 + thud * 0.4
    audio = fade(normalize(audio, 0.7), fade_in_ms=1, fade_out_ms=20)
    save_wav(audio, "footstep_dirt")


def gen_footstep_stone():
    """Footstep on stone/hard surface."""
    duration = 0.12
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Sharp click
    click = noise(duration, 'white')
    click = highpass(click, 500)
    click *= np.exp(-t * 50)

    # Some low end
    thud = noise(duration, 'brown')
    thud = lowpass(thud, 200)
    thud *= np.exp(-t * 60)

    audio = click * 0.7 + thud * 0.3
    audio = fade(normalize(audio, 0.7), fade_in_ms=0, fade_out_ms=15)
    save_wav(audio, "footstep_stone")


def gen_footstep_wood():
    """Footstep on wooden floor."""
    duration = 0.12
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Hollow knock
    knock = sine_wave(180, duration) * np.exp(-t * 40)
    knock += sine_wave(360, duration) * np.exp(-t * 50) * 0.5

    # Creak
    creak = noise(duration, 'pink')
    creak = bandpass(creak, 400, 1200)
    creak *= np.exp(-t * 35)

    audio = knock * 0.6 + creak * 0.4
    audio = fade(normalize(audio, 0.7), fade_in_ms=0, fade_out_ms=20)
    save_wav(audio, "footstep_wood")


def gen_jump():
    """Jump sound - upward pitch sweep."""
    duration = 0.2
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Rising pitch
    freq = 200 + 600 * t / duration
    phase = 2 * np.pi * np.cumsum(freq) / SAMPLE_RATE
    tone = np.sin(phase)

    # Envelope
    env = np.exp(-t * 8) * (1 - np.exp(-t * 100))

    # Add some noise for texture
    swoosh = noise(duration, 'pink')
    swoosh = bandpass(swoosh, 300, 1500)
    swoosh *= np.exp(-t * 15)

    audio = tone * env * 0.6 + swoosh * 0.4
    audio = fade(normalize(audio, 0.8), fade_in_ms=2, fade_out_ms=30)
    save_wav(audio, "jump")


def gen_land():
    """Landing from jump - impact thud."""
    duration = 0.2
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Impact
    impact = noise(duration, 'brown')
    impact = lowpass(impact, 200)
    impact *= np.exp(-t * 25)

    # Some higher crunch
    crunch = noise(duration, 'pink')
    crunch = bandpass(crunch, 200, 1000)
    crunch *= np.exp(-t * 40)

    audio = impact * 0.7 + crunch * 0.3
    audio = fade(normalize(audio, 0.8), fade_in_ms=1, fade_out_ms=30)
    save_wav(audio, "land")


def gen_dodge():
    """Quick dodge/roll sound."""
    duration = 0.25
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Cloth swoosh
    swoosh = noise(duration, 'pink')
    swoosh = bandpass(swoosh, 400, 2000)

    # Quick fade in and out
    env = np.sin(np.pi * t / duration)

    audio = swoosh * env
    audio = fade(normalize(audio, 0.7), fade_in_ms=5, fade_out_ms=40)
    save_wav(audio, "dodge")


# =============================================================================
# UI SOUNDS
# =============================================================================

def gen_ui_click():
    """UI button click."""
    duration = 0.05
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    click = sine_wave(800, duration) * np.exp(-t * 80)
    click += sine_wave(1200, duration) * np.exp(-t * 100) * 0.3

    audio = fade(normalize(click, 0.6), fade_in_ms=0, fade_out_ms=10)
    save_wav(audio, "ui_click")


def gen_ui_hover():
    """UI hover/select sound."""
    duration = 0.08
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    tone = sine_wave(1000, duration) * np.exp(-t * 40)

    audio = fade(normalize(tone, 0.4), fade_in_ms=2, fade_out_ms=15)
    save_wav(audio, "ui_hover")


def gen_ui_confirm():
    """Positive confirmation sound."""
    duration = 0.15
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Rising two-note
    note1 = sine_wave(523, duration * 0.5)  # C5
    note2 = sine_wave(659, duration * 0.5)  # E5

    audio = np.concatenate([note1, note2])
    t_full = np.linspace(0, duration, len(audio))
    audio *= np.exp(-t_full * 10)

    audio = fade(normalize(audio, 0.6), fade_in_ms=2, fade_out_ms=20)
    save_wav(audio, "ui_confirm")


def gen_ui_cancel():
    """Negative/cancel sound."""
    duration = 0.15
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Descending
    note1 = sine_wave(400, duration * 0.5)
    note2 = sine_wave(300, duration * 0.5)

    audio = np.concatenate([note1, note2])
    t_full = np.linspace(0, duration, len(audio))
    audio *= np.exp(-t_full * 8)

    audio = fade(normalize(audio, 0.6), fade_in_ms=2, fade_out_ms=20)
    save_wav(audio, "ui_cancel")


def gen_ui_error():
    """Error/invalid action sound."""
    duration = 0.2
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Buzzy error
    buzz = np.sign(np.sin(2 * np.pi * 150 * t))  # Square wave
    buzz = lowpass(buzz, 400)
    buzz *= np.exp(-t * 10)

    audio = fade(normalize(buzz, 0.5), fade_in_ms=2, fade_out_ms=30)
    save_wav(audio, "ui_error")


def gen_menu_open():
    """Menu opening sound."""
    duration = 0.2
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Ascending sweep
    freq = 300 + 500 * (t / duration)
    phase = 2 * np.pi * np.cumsum(freq) / SAMPLE_RATE
    tone = np.sin(phase)

    env = 1 - (t / duration) ** 2
    audio = tone * env

    audio = fade(normalize(audio, 0.5), fade_in_ms=5, fade_out_ms=30)
    save_wav(audio, "menu_open")


def gen_menu_close():
    """Menu closing sound."""
    duration = 0.15
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Descending sweep
    freq = 800 - 400 * (t / duration)
    phase = 2 * np.pi * np.cumsum(freq) / SAMPLE_RATE
    tone = np.sin(phase)

    env = 1 - (t / duration)
    audio = tone * env

    audio = fade(normalize(audio, 0.5), fade_in_ms=2, fade_out_ms=20)
    save_wav(audio, "menu_close")


# =============================================================================
# ITEM / PICKUP SOUNDS
# =============================================================================

def gen_item_pickup():
    """Picking up item."""
    duration = 0.25
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Shimmery ascending notes
    freqs = [523, 659, 784]  # C E G
    audio = np.zeros(int(SAMPLE_RATE * duration))

    for i, freq in enumerate(freqs):
        start = int(i * 0.03 * SAMPLE_RATE)
        note = sine_wave(freq, duration - i * 0.03)
        note *= np.exp(-np.linspace(0, 1, len(note)) * 8)
        audio[start:start + len(note)] += note * 0.5

    audio = fade(normalize(audio, 0.7), fade_in_ms=2, fade_out_ms=40)
    save_wav(audio, "item_pickup")


def gen_coin_pickup():
    """Coin/gold pickup."""
    duration = 0.2
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # High metallic ping
    ping = sine_wave(2000, duration) * np.exp(-t * 20)
    ping += sine_wave(3000, duration) * np.exp(-t * 25) * 0.5
    ping += sine_wave(1500, duration) * np.exp(-t * 15) * 0.3

    audio = fade(normalize(ping, 0.6), fade_in_ms=0, fade_out_ms=30)
    save_wav(audio, "coin_pickup")


def gen_health_pickup():
    """Health restore sound."""
    duration = 0.4
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Warm ascending arpeggio
    notes = []
    note_dur = 0.1
    for i, freq in enumerate([261, 329, 392, 523]):  # C E G C
        note = sine_wave(freq, note_dur)
        note *= np.exp(-np.linspace(0, 1, len(note)) * 5)
        notes.append(note)

    audio = np.concatenate(notes)

    # Pad to duration
    if len(audio) < int(SAMPLE_RATE * duration):
        audio = np.pad(audio, (0, int(SAMPLE_RATE * duration) - len(audio)))

    audio = fade(normalize(audio, 0.6), fade_in_ms=5, fade_out_ms=60)
    save_wav(audio, "health_pickup")


def gen_powerup():
    """Power-up acquired."""
    duration = 0.5
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Rising sweep with harmonics
    freq = 200 + 800 * (t / duration) ** 2
    phase = 2 * np.pi * np.cumsum(freq) / SAMPLE_RATE

    audio = np.sin(phase)
    audio += np.sin(phase * 2) * 0.3  # Octave
    audio += np.sin(phase * 3) * 0.15  # Fifth

    env = np.sin(np.pi * t / duration) ** 0.3
    audio *= env

    audio = fade(normalize(audio, 0.7), fade_in_ms=10, fade_out_ms=80)
    save_wav(audio, "powerup")


# =============================================================================
# ENVIRONMENTAL / AMBIENT SOUNDS
# =============================================================================

def gen_door_open():
    """Door opening creak."""
    duration = 0.5
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Creaking modulated noise
    mod = np.sin(2 * np.pi * 3 * t) * 0.5 + 0.5
    creak = noise(duration, 'pink')
    creak = bandpass(creak, 300, 1500)
    creak *= mod

    # Low rumble
    rumble = noise(duration, 'brown')
    rumble = lowpass(rumble, 150)

    env = np.ones_like(t)
    env[-int(0.1 * SAMPLE_RATE):] = np.linspace(1, 0, int(0.1 * SAMPLE_RATE))

    audio = (creak * 0.6 + rumble * 0.4) * env
    audio = fade(normalize(audio, 0.7), fade_in_ms=20, fade_out_ms=80)
    save_wav(audio, "door_open")


def gen_door_close():
    """Door closing thud."""
    duration = 0.3
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Thud
    thud = noise(duration, 'brown')
    thud = lowpass(thud, 200)
    thud *= np.exp(-t * 15)

    # Latch click
    click = noise(0.05, 'white')
    click = highpass(click, 1000)
    click *= np.exp(-np.linspace(0, 1, len(click)) * 50)

    audio = thud.copy()
    click_start = int(0.05 * SAMPLE_RATE)
    audio[click_start:click_start + len(click)] += click * 0.5

    audio = fade(normalize(audio, 0.8), fade_in_ms=2, fade_out_ms=50)
    save_wav(audio, "door_close")


def gen_chest_open():
    """Treasure chest opening."""
    duration = 0.6
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Creaky hinge
    creak_freq = 400 + 200 * np.sin(2 * np.pi * 2 * t)
    creak = np.sin(2 * np.pi * np.cumsum(creak_freq) / SAMPLE_RATE)
    creak *= bandpass(noise(duration, 'pink'), 300, 2000)

    env = np.sin(np.pi * t / duration) ** 0.5
    creak *= env * 0.5

    # Magical shimmer at the end
    shimmer_start = int(0.3 * SAMPLE_RATE)
    shimmer = np.zeros_like(t)
    shimmer_len = len(t) - shimmer_start
    shimmer_t = np.linspace(0, duration * 0.7, shimmer_len)

    for freq in [1000, 1500, 2000, 2500]:
        shimmer[shimmer_start:] += np.sin(2 * np.pi * freq * shimmer_t) * np.exp(-shimmer_t * 4) * 0.2

    audio = creak + shimmer
    audio = fade(normalize(audio, 0.7), fade_in_ms=10, fade_out_ms=100)
    save_wav(audio, "chest_open")


def gen_water_splash():
    """Water splash."""
    duration = 0.4
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    splash = noise(duration, 'white')
    splash = bandpass(splash, 200, 4000)
    splash *= np.exp(-t * 10)

    # Bubbles
    for i in range(5):
        bubble_start = int(np.random.uniform(0.05, 0.2) * SAMPLE_RATE)
        bubble_dur = np.random.uniform(0.05, 0.1)
        bubble_freq = np.random.uniform(300, 600)
        bubble = sine_wave(bubble_freq, bubble_dur)
        bubble *= np.exp(-np.linspace(0, 1, len(bubble)) * 20)

        if bubble_start + len(bubble) < len(splash):
            splash[bubble_start:bubble_start + len(bubble)] += bubble * 0.2

    audio = fade(normalize(splash, 0.8), fade_in_ms=2, fade_out_ms=60)
    save_wav(audio, "water_splash")


def gen_fire_crackle():
    """Fire crackling loop segment."""
    duration = 1.0
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Base crackle
    crackle = noise(duration, 'brown')
    crackle = bandpass(crackle, 100, 2000)

    # Random pops
    for _ in range(15):
        pop_pos = int(np.random.uniform(0, duration) * SAMPLE_RATE)
        pop_len = int(np.random.uniform(0.01, 0.05) * SAMPLE_RATE)
        if pop_pos + pop_len < len(crackle):
            pop = np.random.randn(pop_len)  # Generate exact number of samples
            pop = highpass(pop, 500)
            pop *= np.exp(-np.linspace(0, 1, pop_len) * 30)
            crackle[pop_pos:pop_pos + pop_len] += pop * np.random.uniform(0.5, 1.5)

    # Low rumble
    rumble = noise(duration, 'brown')
    rumble = lowpass(rumble, 100)

    audio = crackle * 0.7 + rumble * 0.3
    audio = fade(normalize(audio, 0.6), fade_in_ms=50, fade_out_ms=50)
    save_wav(audio, "fire_crackle")


# =============================================================================
# SPECIAL / MAGIC SOUNDS
# =============================================================================

def gen_magic_cast():
    """Spell casting sound."""
    duration = 0.5
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Rising whoosh
    freq = 200 + 1000 * (t / duration) ** 0.5
    phase = 2 * np.pi * np.cumsum(freq) / SAMPLE_RATE

    tone = np.sin(phase) + np.sin(phase * 1.5) * 0.3

    # Add shimmer
    shimmer = noise(duration, 'pink')
    shimmer = bandpass(shimmer, 2000, 6000)

    env = np.sin(np.pi * t / duration) ** 0.3

    audio = (tone * 0.5 + shimmer * 0.5) * env
    audio = fade(normalize(audio, 0.8), fade_in_ms=10, fade_out_ms=80)
    save_wav(audio, "magic_cast")


def gen_magic_hit():
    """Magic projectile impact."""
    duration = 0.3
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Impact with harmonic content
    impact = fm_synthesis(300, 200, 5, duration)
    impact *= np.exp(-t * 12)

    # Sparkle
    sparkle = noise(duration, 'white')
    sparkle = highpass(sparkle, 3000)
    sparkle *= np.exp(-t * 20)

    audio = impact * 0.6 + sparkle * 0.4
    audio = fade(normalize(audio, 0.8), fade_in_ms=1, fade_out_ms=50)
    save_wav(audio, "magic_hit")


def gen_teleport():
    """Teleport/warp sound."""
    duration = 0.4
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Descending then ascending sweep
    mid = duration / 2
    freq = np.where(t < mid,
                    1000 - 800 * (t / mid),
                    200 + 800 * ((t - mid) / mid))

    phase = 2 * np.pi * np.cumsum(freq) / SAMPLE_RATE
    tone = np.sin(phase)

    # Shimmer overlay
    shimmer = noise(duration, 'pink')
    shimmer = bandpass(shimmer, 1000, 5000)

    env = 1 - np.abs(2 * t / duration - 1)

    audio = (tone * 0.6 + shimmer * 0.4) * env
    audio = fade(normalize(audio, 0.8), fade_in_ms=5, fade_out_ms=50)
    save_wav(audio, "teleport")


def gen_level_up():
    """Level up fanfare."""
    duration = 0.8

    # Triumphant arpeggio
    notes_data = [
        (261.63, 0.15),  # C4
        (329.63, 0.15),  # E4
        (392.00, 0.15),  # G4
        (523.25, 0.35),  # C5 (held longer)
    ]

    audio = np.array([])
    for freq, dur in notes_data:
        t = np.linspace(0, dur, int(SAMPLE_RATE * dur))
        note = np.sin(2 * np.pi * freq * t)
        note += np.sin(2 * np.pi * freq * 2 * t) * 0.3  # Octave
        note *= np.exp(-t * 3)
        audio = np.concatenate([audio, note])

    # Add sparkle overlay
    full_t = np.linspace(0, duration, len(audio))
    sparkle = noise(len(audio) / SAMPLE_RATE, 'white')
    sparkle = highpass(sparkle[:len(audio)], 4000)
    sparkle *= np.exp(-full_t * 3) * 0.3

    audio += sparkle
    audio = fade(normalize(audio, 0.8), fade_in_ms=5, fade_out_ms=100)
    save_wav(audio, "level_up")


# =============================================================================
# NOTIFICATION SOUNDS
# =============================================================================

def gen_notification():
    """General notification ping."""
    duration = 0.3
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Pleasant two-tone
    tone = sine_wave(880, duration) * 0.6
    tone += sine_wave(1320, duration) * 0.4
    tone *= np.exp(-t * 8)

    audio = fade(normalize(tone, 0.6), fade_in_ms=5, fade_out_ms=50)
    save_wav(audio, "notification")


def gen_quest_complete():
    """Quest completed jingle."""
    duration = 0.6

    notes = [392, 440, 523, 659]  # G A C E
    audio = np.array([])

    for freq in notes:
        t = np.linspace(0, 0.12, int(SAMPLE_RATE * 0.12))
        note = np.sin(2 * np.pi * freq * t)
        note *= np.exp(-t * 8)
        audio = np.concatenate([audio, note])

    # Pad and add reverb
    audio = np.pad(audio, (0, int(0.2 * SAMPLE_RATE)))
    audio = reverb_simple(audio, decay=0.2, delay_ms=40)

    audio = fade(normalize(audio, 0.7), fade_in_ms=5, fade_out_ms=80)
    save_wav(audio, "quest_complete")


def gen_warning():
    """Warning/alert sound."""
    duration = 0.4
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Urgent pulsing tone
    pulse = np.sin(2 * np.pi * 8 * t) * 0.3 + 0.7
    tone = sine_wave(600, duration) * pulse
    tone += sine_wave(800, duration) * pulse * 0.5

    tone *= np.exp(-t * 3)

    audio = fade(normalize(tone, 0.7), fade_in_ms=5, fade_out_ms=50)
    save_wav(audio, "warning")


# =============================================================================
# MAIN
# =============================================================================

# All sound generators
SOUND_GENERATORS = {
    # Combat
    'sword_hit': gen_sword_hit,
    'sword_swing': gen_sword_swing,
    'parry': gen_parry,
    'player_hurt': gen_player_hurt,
    'enemy_hurt': gen_enemy_hurt,
    'enemy_death': gen_enemy_death,
    'critical_hit': gen_critical_hit,

    # Movement
    'footstep_dirt': gen_footstep_dirt,
    'footstep_stone': gen_footstep_stone,
    'footstep_wood': gen_footstep_wood,
    'jump': gen_jump,
    'land': gen_land,
    'dodge': gen_dodge,

    # UI
    'ui_click': gen_ui_click,
    'ui_hover': gen_ui_hover,
    'ui_confirm': gen_ui_confirm,
    'ui_cancel': gen_ui_cancel,
    'ui_error': gen_ui_error,
    'menu_open': gen_menu_open,
    'menu_close': gen_menu_close,

    # Items
    'item_pickup': gen_item_pickup,
    'coin_pickup': gen_coin_pickup,
    'health_pickup': gen_health_pickup,
    'powerup': gen_powerup,

    # Environment
    'door_open': gen_door_open,
    'door_close': gen_door_close,
    'chest_open': gen_chest_open,
    'water_splash': gen_water_splash,
    'fire_crackle': gen_fire_crackle,

    # Magic/Special
    'magic_cast': gen_magic_cast,
    'magic_hit': gen_magic_hit,
    'teleport': gen_teleport,
    'level_up': gen_level_up,

    # Notifications
    'notification': gen_notification,
    'quest_complete': gen_quest_complete,
    'warning': gen_warning,
}


def main():
    parser = argparse.ArgumentParser(description='Generate procedural sound effects')
    parser.add_argument('sounds', nargs='*', help='Specific sounds to generate')
    parser.add_argument('--list', action='store_true', help='List available sounds')
    args = parser.parse_args()

    if args.list:
        print("Available sounds:")
        for category, sounds in [
            ("Combat", ['sword_hit', 'sword_swing', 'parry', 'player_hurt', 'enemy_hurt', 'enemy_death', 'critical_hit']),
            ("Movement", ['footstep_dirt', 'footstep_stone', 'footstep_wood', 'jump', 'land', 'dodge']),
            ("UI", ['ui_click', 'ui_hover', 'ui_confirm', 'ui_cancel', 'ui_error', 'menu_open', 'menu_close']),
            ("Items", ['item_pickup', 'coin_pickup', 'health_pickup', 'powerup']),
            ("Environment", ['door_open', 'door_close', 'chest_open', 'water_splash', 'fire_crackle']),
            ("Magic", ['magic_cast', 'magic_hit', 'teleport', 'level_up']),
            ("Notifications", ['notification', 'quest_complete', 'warning']),
        ]:
            print(f"\n  {category}:")
            for s in sounds:
                print(f"    - {s}")
        return

    sounds_to_generate = args.sounds if args.sounds else SOUND_GENERATORS.keys()

    print(f"Generating sound effects to {OUTPUT_DIR}")
    print("=" * 50)

    for sound_name in sounds_to_generate:
        if sound_name in SOUND_GENERATORS:
            SOUND_GENERATORS[sound_name]()
        else:
            print(f"  Unknown sound: {sound_name}")

    print("=" * 50)
    print("Done!")


if __name__ == '__main__':
    main()
