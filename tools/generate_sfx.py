"""Reproduce Outpost Exodus's original procedural SFX; no external samples.

Python standard library only. Every texture uses an independent fixed seed.
Run with --check to verify the checked-in PCM, headroom, fades and provenance.
"""
from array import array
import argparse
import hashlib
import io
import math
from pathlib import Path
import random
import struct
import wave

RATE = 22050
TARGET = Path(__file__).resolve().parents[1] / "assets/audio"
# Short, layered physical textures: dry mechanisms, muted metal and wooden taps.
# The warning deliberately has a soft onset and a low, non-siren register.
SPECS = {
    "shot_a": (0.145, 3901), "shot_b": (0.165, 3902),
    "impact": (0.160, 3903), "loot": (0.340, 3904),
    "confirm": (0.120, 3905), "reject": (0.200, 3906),
    "build": (0.300, 3907), "warning": (0.580, 3908),
}


def tone(t, hz, decay, gain=1.0):
    return math.sin(math.tau * hz * t) * math.exp(-t * decay) * gain


def tap(t, start, noise, hz, gain=1.0):
    age = t - start
    if age < 0:
        return 0.0
    attack = min(1.0, age / 0.0018)
    return attack * (tone(age, hz, 55, 0.5) + noise * math.exp(-age * 95) * 0.35) * gain


def synthesize(name, duration, seed):
    rng = random.Random(seed)
    values = []
    low = 0.0
    previous_noise = 0.0
    for i in range(round(RATE * duration)):
        t = i / RATE
        noise = rng.uniform(-1, 1)
        low = low * 0.77 + noise * 0.23
        high = noise - previous_noise
        previous_noise = noise
        if name.startswith("shot"):
            body = 104 if name == "shot_a" else 91
            # Noise crack, falling pressure body and a tiny returning bolt.
            value = (high * math.exp(-t * 105) * 0.34
                     + low * math.exp(-t * 35) * 0.8
                     + math.sin(math.tau * (body * t + 19 * (1 - math.exp(-t * 45)) / 45)) * math.exp(-t * 48) * 0.42
                     + tap(t, 0.042, noise, 680, 0.2))
        elif name == "impact":
            value = (low * math.exp(-t * 37) * 0.7
                     + tone(t, 83, 40, 0.6) + tap(t, 0.006, noise, 241, 0.3))
        elif name == "loot":
            value = 0.0
            for start, hz, gain in [(0.0, 740, 0.4), (0.065, 1110, 0.36), (0.130, 1480, 0.28)]:
                age = t - start
                if age >= 0:
                    value += min(1.0, age / 0.003) * (tone(age, hz, 22, gain) + tone(age, hz * 2.67, 48, gain * 0.12))
            value += tap(t, 0.0, noise, 260, 0.18)
        elif name == "confirm":
            value = tap(t, 0.0, noise, 530, 0.65) + tap(t, 0.028, noise, 795, 0.5)
        elif name == "reject":
            value = (tap(t, 0.0, noise, 205, 0.6) + tap(t, 0.062, noise, 154, 0.55)
                     + low * math.exp(-t * 25) * 0.16)
        elif name == "build":
            value = (tap(t, 0.0, noise, 330, 0.6) + tap(t, 0.070, noise, 410, 0.55)
                     + tap(t, 0.145, noise, 660, 0.48))
            if t >= 0.145:
                value += tone(t - 0.145, 990, 35, 0.12)
        else:
            value = 0.0
            for start in [0.0, 0.245]:
                age = t - start
                if age >= 0:
                    env = min(1.0, age / 0.018) * math.exp(-age * 15)
                    value += env * (math.sin(math.tau * 294 * age) * 0.5
                                    + math.sin(math.tau * 441 * age) * 0.16
                                    + low * 0.035)
        # Common short fades eliminate edge discontinuities, retaining transients.
        fade = min(1.0, t / 0.0015, (duration - t) / 0.018)
        values.append(value * max(0.0, fade))
    # Fixed per-file normalization reserves >5 dB PCM headroom. Runtime voices
    # add another 12 dB (UI) / 18 dB (world), before user bus/master controls.
    peak = max(abs(value) for value in values)
    pcm = array("h", (round(value / peak * 0.54 * 32767) for value in values))
    # Explicit little endian PCM is reproducible on all Python architectures.
    return struct.pack("<" + "h" * len(pcm), *pcm)


def render(name, duration, seed):
    pcm = synthesize(name, duration, seed)
    output = io.BytesIO()
    with wave.open(output, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(pcm)
    return output.getvalue(), pcm


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify without writing")
    args = parser.parse_args()
    failures = []
    total = 0
    bundle = hashlib.sha256()
    for name, (duration, seed) in SPECS.items():
        expected, pcm = render(name, duration, seed)
        path = TARGET / f"sfx_{name}.wav"
        if args.check:
            if not path.exists() or path.read_bytes() != expected:
                failures.append(f"{path.name}: missing or not reproducible")
        else:
            TARGET.mkdir(parents=True, exist_ok=True)
            path.write_bytes(expected)
        samples = struct.unpack("<" + "h" * (len(pcm) // 2), pcm)
        peak = max(abs(s) for s in samples) / 32768
        rms = math.sqrt(sum(s * s for s in samples) / len(samples)) / 32768
        dc = abs(sum(samples) / len(samples)) / 32768
        if not 0.50 <= peak <= 0.55 or not 0.015 <= rms < 0.30 or dc > 0.02:
            failures.append(f"{path.name}: amplitude bounds peak={peak} rms={rms} dc={dc}")
        if abs(samples[0]) > 1 or abs(samples[-1]) > 200:
            failures.append(f"{path.name}: edge fade discontinuity")
        total += len(expected)
        bundle.update(path.name.encode("ascii") + b"\0" + expected)
        print(f"{path.name} {duration:.3f}s {len(expected)} bytes peak={peak:.4f} rms={rms:.4f} sha256={hashlib.sha256(expected).hexdigest()}")
    print(f"Original standard-library synthesis: {len(SPECS)} mono PCM16/{RATE}Hz files, {total} bytes; bundle_sha256={bundle.hexdigest()}")
    if failures:
        raise SystemExit("\n".join(failures))


if __name__ == "__main__":
    main()
