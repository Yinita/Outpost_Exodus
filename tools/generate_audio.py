"""Reproduce the original quiet travel ambience without external samples.

The default command writes assets/audio/canyon_ambient.wav. --check reproduces
it in memory and compares bytes without creating, repairing or rewriting files.
PCM sample byte order is explicitly little endian, independent of the host.
"""
import argparse
import hashlib
import io
import math
from pathlib import Path
import random
import struct
import wave

RATE = 22050
DURATION = 24
TARGET = Path(__file__).resolve().parents[1] / "assets/audio/canyon_ambient.wav"
NOTES = [(0, 52), (2, 59), (4, 62), (7, 55), (10, 57), (12, 52),
         (14, 64), (16, 62), (19, 59), (22, 55)]


def synthesize_pcm() -> bytes:
    rng = random.Random(7214)
    samples = []
    wind = 0.0
    for i in range(RATE * DURATION):
        t = i / RATE
        wind = wind * 0.985 + rng.uniform(-1, 1) * 0.015
        value = wind * 0.045
        # Sparse plucked fifths and a soft four-bar low drone.
        for start, midi in NOTES:
            age = t - start
            if 0 <= age < 4:
                hz = 440 * 2 ** ((midi - 69) / 12)
                env = min(1.0, age / 0.025) * math.exp(-age * 1.45)
                value += env * (math.sin(math.tau * hz * age) * 0.11
                                + math.sin(math.tau * hz * 2.002 * age) * 0.027
                                + math.sin(math.tau * hz * 3 * age) * 0.009)
        drone = math.sin(math.tau * 82.416 * t) + math.sin(math.tau * 123.47 * t) * 0.4
        value += drone * 0.014 * (0.65 + 0.35 * math.sin(math.tau * t / 12))
        fade = min(1.0, t / 0.25, (DURATION - t) / 0.5)
        samples.append(int(max(-1, min(1, value * fade)) * 32767))
    return struct.pack("<" + "h" * len(samples), *samples)


def render_wav() -> bytes:
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(synthesize_pcm())
    return buffer.getvalue()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Compare in memory; never write the target")
    parser.add_argument("--output", type=Path, default=TARGET, help="WAV destination or file to check")
    args = parser.parse_args()
    expected = render_wav()
    sha = hashlib.sha256(expected).hexdigest()
    if args.check:
        if not args.output.is_file():
            print(f"MISSING {args.output}; expected_sha256={sha}; no files written")
            return 1
        actual = args.output.read_bytes()
        if actual != expected:
            actual_sha = hashlib.sha256(actual).hexdigest()
            print(f"MISMATCH {args.output}; expected_sha256={sha}; actual_sha256={actual_sha}; no files written")
            return 1
        print(f"MATCH {args.output.name} {RATE * DURATION} samples {len(expected)} bytes sha256={sha}; check-only")
        return 0
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(expected)
    print(args.output.name, RATE * DURATION, "samples")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
