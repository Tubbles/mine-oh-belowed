#!/usr/bin/env python3
"""Write the placeholder sounds (work item 0068) to data/sounds/.

Usage: tools/make_placeholder_sounds.py [output directory]

The output directory defaults to data/sounds/.

Only the standard library is used (wave and struct write the files), and
the output is deterministic: noise comes from a small generator seeded
per sound, so the same script writes the same bytes. Every file is 16 bit
mono PCM at 22050 Hz.

The table the game reads, data/sounds/sounds.sjson, is written by hand:
it names each file, its volume and whether it is a short effect or a
loop. This script only writes the files, one per id below:

- footstep_<material>: a short filtered noise burst per sound_material
  of data/blocks.sjson (stone, dirt, sand, wood, leaves, snow, metal,
  water). Harder materials are brighter and shorter.
- mine_hit_<tier>: a click per tool tier (0 hands to 3 iron), sharper
  with each tier.
- block_break, block_place: a crunch and a thud.
- ui_move, ui_confirm, ui_back: soft blips.
- hum_burner, hum_electric, hum_fluid: one hum loop per machine family.
- ambience_wind, ambience_water: the biome ambience loops.
- ambience_birds_1 to _3, ambience_insects_1 to _2: short calls of three
  to five chirps or buzzes each, the variants the game plays in clusters
  with long pauses between them (work item 0089).
- rain: the rain loop.
- rocket_launch, capsule_landing, discovery_chime: the launch rumble,
  the landing thud and the chime of a discovered ore.
- mission_control_chime: two short rising notes as a Mission Control line
  starts on the HUD (work item 0069).

A loop ends where it starts: its tail is crossfaded into its head, and
its tones have a whole number of cycles over the loop. The whole set is a
placeholder: recorded sounds replace the files later.
"""

import math
import pathlib
import struct
import sys
import wave

REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parent.parent
SOUNDS_DIRECTORY = REPOSITORY_ROOT / "data" / "sounds"
SAMPLE_RATE = 22050
PEAK = 32767
# Samples of a loop's tail blended into its head.
LOOP_CROSSFADE_SECONDS = 0.25


class Noise:
    """A 32 bit xorshift generator: white noise from -1 to 1."""

    def __init__(self, seed: int):
        self.state = (seed * 2654435761 + 1) & 0xFFFFFFFF or 1

    def next(self) -> float:
        state = self.state
        state ^= (state << 13) & 0xFFFFFFFF
        state ^= state >> 17
        state ^= (state << 5) & 0xFFFFFFFF
        self.state = state
        return state / 0x7FFFFFFF - 1.0


def seed_of(name: str) -> int:
    seed = 2166136261
    for byte in name.encode():
        seed = ((seed ^ byte) * 16777619) & 0xFFFFFFFF
    return seed


def sample_count(seconds: float) -> int:
    return int(round(seconds * SAMPLE_RATE))


def low_pass(samples: list, cutoff_hertz: float) -> list:
    """A one pole low pass filter."""
    factor = 1.0 - math.exp(-2.0 * math.pi * cutoff_hertz / SAMPLE_RATE)
    output, value = [], 0.0
    for sample in samples:
        value += factor * (sample - value)
        output.append(value)
    return output


def high_pass(samples: list, cutoff_hertz: float) -> list:
    smooth = low_pass(samples, cutoff_hertz)
    return [sample - low for sample, low in zip(samples, smooth)]


def band_noise(name: str, seconds: float, low_hertz: float, high_hertz: float) -> list:
    noise = Noise(seed_of(name))
    white = [noise.next() for _ in range(sample_count(seconds))]
    return high_pass(low_pass(white, high_hertz), low_hertz)


def envelope(count: int, attack_seconds: float, decay_seconds: float) -> list:
    """A linear attack, then an exponential decay."""
    attack = max(sample_count(attack_seconds), 1)
    values = []
    for index in range(count):
        if index < attack:
            values.append(index / attack)
        else:
            values.append(math.exp(-(index - attack) / (decay_seconds * SAMPLE_RATE)))
    return values


def shaped(samples: list, attack_seconds: float, decay_seconds: float) -> list:
    return [sample * gain for sample, gain in zip(samples, envelope(len(samples), attack_seconds, decay_seconds))]


def tone(frequency: float, seconds: float, phase: float = 0.0) -> list:
    return [math.sin(2.0 * math.pi * frequency * index / SAMPLE_RATE + phase) for index in range(sample_count(seconds))]


def sweep(start_hertz: float, end_hertz: float, seconds: float) -> list:
    count = sample_count(seconds)
    samples, phase = [], 0.0
    for index in range(count):
        frequency = start_hertz + (end_hertz - start_hertz) * index / max(count - 1, 1)
        phase += 2.0 * math.pi * frequency / SAMPLE_RATE
        samples.append(math.sin(phase))
    return samples


def mix(*layers) -> list:
    length = max(len(layer) for layer, _ in layers)
    output = [0.0] * length
    for layer, gain in layers:
        for index, sample in enumerate(layer):
            output[index] += sample * gain
    return output


def normalised(samples: list, peak: float) -> list:
    loudest = max((abs(sample) for sample in samples), default=0.0)
    if loudest == 0.0:
        return samples
    return [sample * peak / loudest for sample in samples]


def seamless(samples: list) -> list:
    """The tail crossfaded into the head, the tail dropped: the loop ends
    where it starts."""
    fade = sample_count(LOOP_CROSSFADE_SECONDS)
    body, tail = samples[:-fade], samples[-fade:]
    for index in range(fade):
        weight = index / fade
        body[index] = body[index] * weight + tail[index] * (1.0 - weight)
    return body


def loop_noise(name: str, seconds: float, low_hertz: float, high_hertz: float) -> list:
    return band_noise(name, seconds + LOOP_CROSSFADE_SECONDS, low_hertz, high_hertz)


# Effects.

FOOTSTEP_MATERIALS = {
    # low and high cut in hertz, decay in seconds
    "stone": (500.0, 4000.0, 0.035),
    "dirt": (120.0, 900.0, 0.05),
    "sand": (800.0, 5000.0, 0.07),
    "wood": (200.0, 1400.0, 0.04),
    "leaves": (1500.0, 7000.0, 0.08),
    "snow": (300.0, 2500.0, 0.09),
    "metal": (900.0, 6000.0, 0.03),
    "water": (200.0, 2000.0, 0.12),
}


def footstep(material: str) -> list:
    low, high, decay = FOOTSTEP_MATERIALS[material]
    burst = shaped(band_noise(f"footstep_{material}", 0.25, low, high), 0.004, decay)
    if material == "metal":
        ring = shaped(tone(1320.0, 0.25), 0.002, 0.06)
        burst = mix((burst, 1.0), (ring, 0.25))
    if material == "water":
        splash = shaped(sweep(900.0, 300.0, 0.25), 0.01, 0.05)
        burst = mix((burst, 1.0), (splash, 0.3))
    return normalised(burst, 0.5)


def mine_hit(tier: int) -> list:
    # Hands thump, iron rings: brighter, shorter and with more ring per tier.
    high = 1200.0 + tier * 1800.0
    decay = 0.05 - tier * 0.01
    click = shaped(band_noise(f"mine_hit_{tier}", 0.15, 150.0 + tier * 300.0, high), 0.002, decay)
    ring = shaped(tone(600.0 + tier * 500.0, 0.15), 0.001, 0.02 + tier * 0.01)
    return normalised(mix((click, 1.0), (ring, 0.1 * tier)), 0.55)


def block_break() -> list:
    crunch = shaped(band_noise("block_break", 0.35, 150.0, 3000.0), 0.005, 0.09)
    grains = shaped(band_noise("block_break_grains", 0.35, 2000.0, 7000.0), 0.02, 0.12)
    return normalised(mix((crunch, 1.0), (grains, 0.3)), 0.6)


def block_place() -> list:
    thud = shaped(sweep(180.0, 70.0, 0.2), 0.003, 0.05)
    tap = shaped(band_noise("block_place", 0.2, 200.0, 1500.0), 0.002, 0.025)
    return normalised(mix((thud, 1.0), (tap, 0.4)), 0.6)


def blip(frequency: float, seconds: float) -> list:
    return normalised(shaped(tone(frequency, seconds), 0.003, seconds / 4), 0.3)


def rocket_launch() -> list:
    seconds = 4.0
    rumble = band_noise("rocket_launch", seconds, 25.0, 400.0)
    roar = band_noise("rocket_launch_roar", seconds, 300.0, 2500.0)
    count = len(rumble)
    ramp = [min(index / (0.4 * SAMPLE_RATE), 1.0) * (1.0 - index / count) ** 0.7 for index in range(count)]
    return normalised([(low + 0.3 * high) * gain for low, high, gain in zip(rumble, roar, ramp)], 0.8)


def capsule_landing() -> list:
    thud = shaped(sweep(120.0, 40.0, 0.6), 0.004, 0.15)
    debris = shaped(band_noise("capsule_landing", 0.6, 100.0, 1800.0), 0.003, 0.12)
    return normalised(mix((thud, 1.0), (debris, 0.5)), 0.75)


def discovery_chime() -> list:
    # Three rising notes of a major triad, each ringing out.
    notes = []
    for index, frequency in enumerate((659.25, 830.61, 987.77)):
        silence = [0.0] * sample_count(index * 0.12)
        notes.append((silence + shaped(tone(frequency, 1.0), 0.005, 0.25), 1.0))
    return normalised(mix(*notes), 0.45)


def mission_control_chime() -> list:
    # Two short notes a fourth apart, the second after the first.
    first = shaped(tone(783.99, 0.18), 0.004, 0.05)
    second = [0.0] * sample_count(0.09) + shaped(tone(1046.50, 0.3), 0.004, 0.09)
    return normalised(mix((first, 1.0), (second, 1.0)), 0.4)


# Loops.


def hum(name: str, base_hertz: float, harmonics: list, noise_gain: float, low: float, high: float) -> list:
    seconds = 2.0
    layers = [(tone(base_hertz * multiple, seconds), gain) for multiple, gain in harmonics]
    # Whole cycles over the loop, so the tones need no crossfade; the
    # noise gets one.
    noise = seamless(loop_noise(name, seconds, low, high))
    layers.append((noise, noise_gain))
    return normalised(mix(*layers), 0.35)


def ambience_wind() -> list:
    seconds = 6.0
    gust = loop_noise("ambience_wind", seconds, 80.0, 700.0)
    count = len(gust)
    swell = [0.6 + 0.4 * math.sin(2.0 * math.pi * index / count * 2) for index in range(count)]
    return normalised(seamless([sample * gain for sample, gain in zip(gust, swell)]), 0.4)


def placed(calls: list, seconds: float) -> list:
    """Each (start in seconds, samples) added into a silence this long."""
    output = [0.0] * sample_count(seconds)
    for start, call in calls:
        offset = sample_count(start)
        for index, sample in enumerate(call[: len(output) - offset]):
            output[offset + index] += sample
    return output


def ambience_birds(variant: int) -> list:
    # Three to five rising chirps, their spacing and pitch per variant.
    noise = Noise(seed_of(f"ambience_birds_{variant}"))
    chirps, start = [], 0.02
    for _ in range(3 + variant % 3):
        pitch = 2600.0 + 600.0 * noise.next()
        length = 0.07 + 0.03 * abs(noise.next())
        chirps.append((start, shaped(sweep(pitch, pitch * (1.2 + 0.15 * noise.next()), length), 0.01, 0.03)))
        start += length + 0.06 + 0.08 * abs(noise.next())
    return normalised(placed(chirps, start + 0.1), 0.35)


def ambience_insects(variant: int) -> list:
    # Three to five short chirrs of noise pulsing about 20 times a second.
    noise = Noise(seed_of(f"ambience_insects_{variant}"))
    buzzes, start = [], 0.02
    for index in range(3 + (variant + 1) % 3):
        length = 0.25 + 0.15 * abs(noise.next())
        hiss = band_noise(f"ambience_insects_{variant}_{index}", length, 3000.0, 8000.0)
        rate = 20.0 + 4.0 * noise.next()
        pulse = [0.5 + 0.5 * math.sin(2.0 * math.pi * rate * sample / SAMPLE_RATE) for sample in range(len(hiss))]
        fade = [min(sample / (0.03 * SAMPLE_RATE), (len(hiss) - sample) / (0.05 * SAMPLE_RATE), 1.0) for sample in range(len(hiss))]
        buzzes.append((start, [value * gain * edge for value, gain, edge in zip(hiss, pulse, fade)]))
        start += length + 0.1 + 0.2 * abs(noise.next())
    return normalised(placed(buzzes, start + 0.05), 0.25)


def ambience_water() -> list:
    seconds = 6.0
    lapping = loop_noise("ambience_water", seconds, 100.0, 900.0)
    count = len(lapping)
    waves = [0.5 + 0.5 * math.sin(2.0 * math.pi * index / count * 3) ** 2 for index in range(count)]
    return normalised(seamless([sample * gain for sample, gain in zip(lapping, waves)]), 0.4)


def rain() -> list:
    hiss = seamless(loop_noise("rain", 4.0, 1000.0, 6000.0))
    patter = seamless(loop_noise("rain_patter", 4.0, 300.0, 2000.0))
    return normalised(mix((hiss, 1.0), (patter, 0.5)), 0.4)


def sound_set() -> dict:
    sounds = {f"footstep_{material}": footstep(material) for material in FOOTSTEP_MATERIALS}
    sounds.update({f"mine_hit_{tier}": mine_hit(tier) for tier in range(4)})
    sounds["block_break"] = block_break()
    sounds["block_place"] = block_place()
    sounds["ui_move"] = blip(880.0, 0.05)
    sounds["ui_confirm"] = blip(1320.0, 0.08)
    sounds["ui_back"] = blip(660.0, 0.07)
    sounds["hum_burner"] = hum("hum_burner", 55.0, [(1, 1.0), (2, 0.3)], 0.5, 60.0, 500.0)
    sounds["hum_electric"] = hum("hum_electric", 60.0, [(1, 0.6), (2, 1.0), (3, 0.4), (5, 0.15)], 0.05, 2000.0, 6000.0)
    sounds["hum_fluid"] = hum("hum_fluid", 45.0, [(1, 0.7), (3, 0.2)], 0.8, 200.0, 1500.0)
    sounds["ambience_wind"] = ambience_wind()
    sounds.update({f"ambience_birds_{variant}": ambience_birds(variant) for variant in range(1, 4)})
    sounds.update({f"ambience_insects_{variant}": ambience_insects(variant) for variant in range(1, 3)})
    sounds["ambience_water"] = ambience_water()
    sounds["rain"] = rain()
    sounds["rocket_launch"] = rocket_launch()
    sounds["capsule_landing"] = capsule_landing()
    sounds["discovery_chime"] = discovery_chime()
    sounds["mission_control_chime"] = mission_control_chime()
    return sounds


def write_wave(directory: pathlib.Path, name: str, samples: list) -> None:
    path = directory / f"{name}.wav"
    frames = b"".join(struct.pack("<h", max(-PEAK, min(PEAK, int(round(sample * PEAK))))) for sample in samples)
    with wave.open(str(path), "wb") as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(SAMPLE_RATE)
        file.writeframes(frames)
    print(f"wrote {path}")


def main() -> None:
    directory = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else SOUNDS_DIRECTORY
    directory.mkdir(parents=True, exist_ok=True)
    for name, samples in sound_set().items():
        write_wave(directory, name, samples)


if __name__ == "__main__":
    main()
