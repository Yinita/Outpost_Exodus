"""Reproduce original, quiet synthesized travel ambience. No sampled music/assets."""
from array import array
from pathlib import Path
import math
import random
import wave

RATE = 22050
DURATION = 24
rng = random.Random(7214)
notes = [(0, 52), (2, 59), (4, 62), (7, 55), (10, 57), (12, 52),
         (14, 64), (16, 62), (19, 59), (22, 55)]
samples = array("h")
wind = 0.0
for i in range(RATE * DURATION):
    t = i / RATE
    wind = wind * 0.985 + rng.uniform(-1, 1) * 0.015
    value = wind * 0.045
    # Sparse plucked fifths and a soft four-bar low drone.
    for start, midi in notes:
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
target = Path(__file__).resolve().parents[1] / "assets/audio/canyon_ambient.wav"
target.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(target), "wb") as output:
    output.setnchannels(1)
    output.setsampwidth(2)
    output.setframerate(RATE)
    output.writeframes(samples.tobytes())
print(target.name, len(samples), "samples")
