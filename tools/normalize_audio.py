#!/usr/bin/env python3
"""
Normalize WAV audio files in the audio/ directory to consistent levels.

Targets:
  - audio/sfx/      : peak -6 dB (0.5 linear)
  - audio/generated/ : peak -6 dB (0.5 linear)
  - audio/music/     : peak -3 dB (0.707 linear)
  - audio/ (root)    : peak -6 dB (0.5 linear)

Variant files (e.g., footstep_grass.wav, footstep_grass_2.wav) are normalized
to the same level based on the average RMS of the group.

Files already within 1 dB of target are skipped.
Backups are created as .bak files before modification.
"""

import array
import wave
import struct
import math
import os
import re
import shutil
import sys
from collections import defaultdict

AUDIO_ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "audio")

# Target peak amplitudes (linear scale, where 1.0 = full scale)
TARGET_PEAK_SFX = 0.5       # -6 dB
TARGET_PEAK_GENERATED = 0.5  # -6 dB
TARGET_PEAK_MUSIC = 0.707    # -3 dB
TARGET_PEAK_ROOT = 0.5       # -6 dB

# Tolerance: skip if within 1 dB of target
DB_TOLERANCE = 1.0

# Directories to skip
SKIP_DIRS = {"TODO", "TODO2", "TODO3", "audio"}


def linear_to_db(linear):
    if linear <= 0:
        return -120.0
    return 20.0 * math.log10(linear)


def analyze_wav(filepath):
    """Read a WAV file and return (params, peak_linear, rms_linear).

    Does NOT keep sample data in memory.
    """
    with wave.open(filepath, 'rb') as wf:
        params = wf.getparams()
        nchannels = params.nchannels
        sampwidth = params.sampwidth
        nframes = params.nframes
        raw_data = wf.readframes(nframes)

    if sampwidth == 2:
        # Use array module for fast 16-bit unpacking
        samples = array.array('h')
        samples.frombytes(raw_data)
        if sys.byteorder == 'big':
            samples.byteswap()
        raw_max = 32767.0
        max_val = 0
        sum_sq = 0.0
        for s in samples:
            av = abs(s)
            if av > max_val:
                max_val = av
            sum_sq += s * s
        count = len(samples)
    elif sampwidth == 3:
        raw_max = 8388607.0
        max_val = 0
        sum_sq = 0.0
        count = 0
        for i in range(0, len(raw_data), 3):
            val = raw_data[i] | (raw_data[i+1] << 8) | (raw_data[i+2] << 16)
            if val >= 0x800000:
                val -= 0x1000000
            av = abs(val)
            if av > max_val:
                max_val = av
            sum_sq += val * val
            count += 1
    elif sampwidth == 1:
        raw_max = 127.0
        samples = array.array('B')
        samples.frombytes(raw_data)
        max_val = 0
        sum_sq = 0.0
        for s in samples:
            centered = s - 128
            av = abs(centered)
            if av > max_val:
                max_val = av
            sum_sq += centered * centered
        count = len(samples)
    else:
        raise ValueError(f"Unsupported sample width: {sampwidth}")

    peak = max_val / raw_max if raw_max > 0 else 0.0
    rms = math.sqrt(sum_sq / (raw_max * raw_max * count)) if count > 0 else 0.0

    return params, peak, rms


def normalize_wav_file(filepath, gain):
    """Read a WAV, apply gain, write back. Handles 8/16/24-bit."""
    with wave.open(filepath, 'rb') as wf:
        params = wf.getparams()
        sampwidth = params.sampwidth
        nframes = params.nframes
        raw_data = wf.readframes(nframes)

    if sampwidth == 2:
        samples = array.array('h')
        samples.frombytes(raw_data)
        if sys.byteorder == 'big':
            samples.byteswap()
        max_int = 32767
        min_int = -32768
        for i in range(len(samples)):
            val = int(round(samples[i] * gain))
            if val > max_int:
                val = max_int
            elif val < min_int:
                val = min_int
            samples[i] = val
        if sys.byteorder == 'big':
            samples.byteswap()
        out_data = samples.tobytes()

    elif sampwidth == 3:
        max_int = 8388607
        min_int = -8388608
        out_buf = bytearray(len(raw_data))
        for i in range(0, len(raw_data), 3):
            val = raw_data[i] | (raw_data[i+1] << 8) | (raw_data[i+2] << 16)
            if val >= 0x800000:
                val -= 0x1000000
            val = int(round(val * gain))
            if val > max_int:
                val = max_int
            elif val < min_int:
                val = min_int
            if val < 0:
                val += 0x1000000
            out_buf[i] = val & 0xFF
            out_buf[i+1] = (val >> 8) & 0xFF
            out_buf[i+2] = (val >> 16) & 0xFF
        out_data = bytes(out_buf)

    elif sampwidth == 1:
        samples = array.array('B')
        samples.frombytes(raw_data)
        for i in range(len(samples)):
            val = int(round((samples[i] - 128) * gain)) + 128
            if val > 255:
                val = 255
            elif val < 0:
                val = 0
            samples[i] = val
        out_data = samples.tobytes()
    else:
        raise ValueError(f"Unsupported sample width: {sampwidth}")

    with wave.open(filepath, 'wb') as wf:
        wf.setparams(params)
        wf.writeframes(out_data)


def get_variant_group_name(filename):
    """Extract the base name for variant grouping.

    footstep_grass.wav -> footstep_grass
    footstep_grass_2.wav -> footstep_grass
    birds_ambient_3.wav -> birds_ambient
    sword_swing_3.wav -> sword_swing
    """
    base = os.path.splitext(filename)[0]
    match = re.match(r'^(.+?)(?:_(?:\d+|real))?$', base)
    if match:
        return match.group(1)
    return base


def get_target_peak(filepath):
    """Determine target peak based on file location."""
    rel = os.path.relpath(filepath, AUDIO_ROOT)
    parts = rel.split(os.sep)
    if len(parts) >= 2:
        subdir = parts[0]
        if subdir == "sfx":
            return TARGET_PEAK_SFX
        elif subdir == "generated":
            return TARGET_PEAK_GENERATED
        elif subdir == "music":
            return TARGET_PEAK_MUSIC
    return TARGET_PEAK_ROOT


def collect_wav_files():
    """Collect all WAV files to process (skipping TODO dirs)."""
    files = []
    for dirpath, dirnames, filenames in os.walk(AUDIO_ROOT):
        rel = os.path.relpath(dirpath, AUDIO_ROOT)
        top_dir = rel.split(os.sep)[0]
        if top_dir in SKIP_DIRS:
            continue
        for f in filenames:
            if f.lower().endswith('.wav'):
                files.append(os.path.join(dirpath, f))
    return sorted(files)


def main():
    wav_files = collect_wav_files()
    print(f"Found {len(wav_files)} WAV files to analyze")

    # Phase 1: Analyze all files (stats only, no sample data kept)
    file_stats = {}  # filepath -> (params, peak, rms)
    errors = []

    for i, filepath in enumerate(wav_files):
        rel = os.path.relpath(filepath, AUDIO_ROOT)
        try:
            params, peak, rms = analyze_wav(filepath)
            file_stats[filepath] = (params, peak, rms)
            if (i + 1) % 20 == 0:
                print(f"  Analyzed {i+1}/{len(wav_files)}...")
        except Exception as e:
            errors.append((filepath, str(e)))
            print(f"  ERROR reading {rel}: {e}")

    print(f"  Analyzed {len(file_stats)}/{len(wav_files)} files successfully")
    if errors:
        print(f"  {len(errors)} files had errors and will be skipped.")

    # Phase 2: Group variants by directory
    dir_groups = defaultdict(lambda: defaultdict(list))
    for filepath in file_stats:
        dirpath = os.path.dirname(filepath)
        filename = os.path.basename(filepath)
        group = get_variant_group_name(filename)
        dir_groups[dirpath][group].append(filepath)

    # Phase 3: Calculate gain for each file
    file_gains = {}

    for dirpath, groups in dir_groups.items():
        for group_name, group_files in groups.items():
            target_peak = get_target_peak(group_files[0])

            if len(group_files) > 1:
                # Variant group: use max peak across group for common gain
                max_peak = max(file_stats[f][1] for f in group_files)
                gain = target_peak / max_peak if max_peak > 0 else 1.0
                for f in group_files:
                    file_gains[f] = gain
            else:
                f = group_files[0]
                peak = file_stats[f][1]
                gain = target_peak / peak if peak > 0 else 1.0
                file_gains[f] = gain

    # Phase 4: Apply normalization (re-reads files that need changes)
    modified = []
    skipped = []

    for filepath in sorted(file_gains.keys()):
        gain = file_gains[filepath]
        gain_db = linear_to_db(gain) if gain > 0 else -120.0
        rel_path = os.path.relpath(filepath, AUDIO_ROOT)
        _, peak, rms = file_stats[filepath]
        target_peak = get_target_peak(filepath)

        if abs(gain_db) <= DB_TOLERANCE:
            skipped.append((rel_path, peak, target_peak, gain_db))
            continue

        # Back up file
        bak_path = filepath + ".bak"
        if not os.path.exists(bak_path):
            shutil.copy2(filepath, bak_path)

        # Apply gain
        try:
            normalize_wav_file(filepath, gain)
            modified.append((rel_path, peak, target_peak, gain_db))
            print(f"  Normalized: {rel_path} (gain {gain_db:+.1f} dB)")
        except Exception as e:
            print(f"  ERROR writing {rel_path}: {e}")
            # Restore from backup
            if os.path.exists(bak_path):
                shutil.copy2(bak_path, filepath)

    # Print report
    print()
    print("=" * 78)
    print("NORMALIZATION REPORT")
    print("=" * 78)

    if modified:
        print(f"\nMODIFIED ({len(modified)} files):")
        print(f"  {'File':<50} {'Peak':>6} {'Target':>6} {'Gain dB':>8}")
        print(f"  {'-'*50} {'-'*6} {'-'*6} {'-'*8}")
        for rel_path, peak, target, gain_db in modified:
            print(f"  {rel_path:<50} {peak:>6.3f} {target:>6.3f} {gain_db:>+8.1f}")

    if skipped:
        print(f"\nSKIPPED - already within {DB_TOLERANCE} dB of target ({len(skipped)} files):")
        print(f"  {'File':<50} {'Peak':>6} {'Target':>6} {'Gain dB':>8}")
        print(f"  {'-'*50} {'-'*6} {'-'*6} {'-'*8}")
        for rel_path, peak, target, gain_db in skipped:
            print(f"  {rel_path:<50} {peak:>6.3f} {target:>6.3f} {gain_db:>+8.1f}")

    print(f"\nSummary: {len(modified)} modified, {len(skipped)} skipped, {len(errors)} errors")
    if modified:
        print(f"Backup files saved as .bak alongside originals")


if __name__ == "__main__":
    main()
