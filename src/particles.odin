package game

import "core:math"
import "generation_seed"

// The particle pool (work item 0067): render state in Frame_State, never
// touched by the simulation, discarded on a session change. A fixed pool
// whose next index wraps, so a new particle replaces the oldest one when
// the pool is full. Emitters (render_particles.odin) spawn into it each
// frame with a hash of the frame count and the emitter's cell as the
// random source, so no emitter keeps state; each particle then moves by
// its kind's gravity and drag until it ages out. Pure, no raylib.

PARTICLE_CAPACITY :: 2048
PARTICLE_SEED :: 0x7a47_1c1e
// A long frame (a hitch, a dragged window) advances by at most this.
PARTICLE_MAXIMUM_FRAME_SECONDS :: 0.1
// Particles start this far to either side of their spawn size.
PARTICLE_SIZE_SPREAD :: 0.5
// A particle fades out over the last third of its life.
PARTICLE_FADE_SHARE :: 1.0 / 3.0

Particle_Kind :: enum u8 {
	Debris,
	Puff,
	Smoke,
	Steam,
	Spark,
	Flame,
	Exhaust,
}

// A free slot has life_seconds 0.
Particle :: struct {
	position:     [3]f32,
	velocity:     [3]f32,
	age_seconds:  f32,
	life_seconds: f32,
	size:         f32,
	color:        [4]u8,
	kind:         Particle_Kind,
}

Particle_System :: struct {
	particles: [PARTICLE_CAPACITY]Particle,
	next:      int,
}

// gravity in blocks per second squared (negative falls), drag the share of
// the velocity lost per second, speed the sideways launch speed (each
// particle 1 +- speed_spread / 2 of it), rise the upward launch speed,
// growth the size at the end of life as a multiple of the start, glows
// for the kinds the sky light does not darken.
Particle_Behaviour :: struct {
	gravity:      f32,
	drag:         f32,
	speed:        f32,
	speed_spread: f32,
	rise:         f32,
	life_seconds: f32,
	size:         f32,
	growth:       f32,
	glows:        bool,
}

// Debris falls and bounces off nothing, smoke rises and slows, steam rises
// fast and fades, sparks fall, a flame licks up and shrinks, exhaust rises
// little and spreads.
@(rodata)
particle_behaviours := [Particle_Kind]Particle_Behaviour {
	.Debris  = {gravity = -18, drag = 0.5, speed = 2.0, speed_spread = 1, rise = 3.0, life_seconds = 0.8, size = 0.08, growth = 1},
	.Puff    = {gravity = 0.5, drag = 3.0, speed = 2.5, speed_spread = 1, rise = 0.8, life_seconds = 0.7, size = 0.25, growth = 2},
	.Smoke   = {gravity = 0.6, drag = 0.8, speed = 0.3, speed_spread = 1, rise = 1.0, life_seconds = 3.5, size = 0.35, growth = 3},
	.Steam   = {gravity = 1.5, drag = 0.5, speed = 0.4, speed_spread = 1, rise = 2.5, life_seconds = 1.4, size = 0.3, growth = 2.5},
	.Spark   = {gravity = -12, drag = 0.3, speed = 2.5, speed_spread = 1, rise = 2.5, life_seconds = 0.6, size = 0.06, growth = 1, glows = true},
	.Flame   = {gravity = 3.0, drag = 1.0, speed = 0.3, speed_spread = 1, rise = 2.0, life_seconds = 0.5, size = 0.45, growth = 0.4, glows = true},
	.Exhaust = {gravity = 0.4, drag = 1.5, speed = 4.0, speed_spread = 1, rise = 0.5, life_seconds = 1.2, size = 0.8, growth = 2.5, glows = true},
}

// rate in particles per second; spread the radius around position the
// particles start in, in blocks.
Emitter :: struct {
	position: [3]f32,
	kind:     Particle_Kind,
	rate:     f32,
	color:    [4]u8,
	spread:   f32,
}

particle_is_live :: proc(particle: Particle) -> bool {
	return particle.life_seconds > 0
}

live_particle_count :: proc(system: ^Particle_System) -> int {
	count := 0
	for particle in system.particles {
		if particle_is_live(particle) {
			count += 1
		}
	}
	return count
}

// Into the next slot, replacing whatever was there: the oldest particle.
add_particle :: proc(system: ^Particle_System, particle: Particle) {
	system.particles[system.next] = particle
	system.next = (system.next + 1) % PARTICLE_CAPACITY
}

// The velocity after seconds of the kind's gravity and drag.
particle_velocity_after :: proc(velocity: [3]f32, behaviour: Particle_Behaviour, seconds: f32) -> [3]f32 {
	result := velocity + [3]f32{0, behaviour.gravity * seconds, 0}
	return result * max(1 - behaviour.drag * seconds, 0)
}

advance_particle :: proc(particle: Particle, seconds: f32) -> Particle {
	result := particle
	result.velocity = particle_velocity_after(particle.velocity, particle_behaviours[particle.kind], seconds)
	result.position += result.velocity * seconds
	result.age_seconds += seconds
	if result.age_seconds >= result.life_seconds {
		return {}
	}
	return result
}

advance_particles :: proc(system: ^Particle_System, seconds: f32) {
	for &particle in system.particles {
		if particle_is_live(particle) {
			particle = advance_particle(particle, seconds)
		}
	}
}

// The whole particles due this frame at the rate: the fractional part
// becomes one more particle when the random key's unit value is below it,
// so the rate holds on average without a remainder kept per emitter.
particle_spawn_count :: proc(rate, seconds: f32, random_key: u64) -> int {
	return int(math.floor(max(rate * seconds, 0) + hash_unit(random_key)))
}

// A new particle of the emitter's kind, from the key's hash: a start
// within the spread, a sideways speed in any direction, a rise, a size.
make_particle :: proc(emitter: Emitter, key: u64) -> Particle {
	behaviour := particle_behaviours[emitter.kind]
	offset_angle := hash_unit(key) * math.TAU
	offset := math.sqrt(hash_unit(key + 1)) * emitter.spread
	angle := hash_unit(key + 2) * math.TAU
	speed := behaviour.speed * (1 - behaviour.speed_spread / 2 + behaviour.speed_spread * hash_unit(key + 3))
	rise := behaviour.rise * (0.5 + hash_unit(key + 4))
	return Particle {
		position = emitter.position + {math.cos(offset_angle) * offset, 0, math.sin(offset_angle) * offset},
		velocity = {math.cos(angle) * speed, rise, math.sin(angle) * speed},
		life_seconds = behaviour.life_seconds * (0.75 + 0.5 * hash_unit(key + 5)),
		size = behaviour.size * (1 - PARTICLE_SIZE_SPREAD / 2 + PARTICLE_SIZE_SPREAD * hash_unit(key + 6)),
		color = emitter.color,
		kind = emitter.kind,
	}
}

// Eight keys apart per particle, which make_particle uses up.
particle_key :: proc(random_key: u64, index: int) -> u64 {
	return generation_seed.hash_u64(random_key + u64(index) * 8)
}

spawn_particle_count :: proc(system: ^Particle_System, emitter: Emitter, count: int, random_key: u64) {
	for index in 0 ..< count {
		add_particle(system, make_particle(emitter, particle_key(random_key, index)))
	}
}

// The emitter's rate over seconds; the same key always gives the same
// particles.
spawn_particles :: proc(system: ^Particle_System, emitter: Emitter, seconds: f32, random_key: u64) {
	spawn_particle_count(system, emitter, particle_spawn_count(emitter.rate, seconds, random_key), random_key)
}

// The random source of an emitter in a frame: the frame count, the cell
// the emitter stands in and its kind.
emitter_random_key :: proc(frame_count: u64, emitter: Emitter) -> u64 {
	key := generation_seed.hash_u64(u64(PARTICLE_SEED) ~ frame_count)
	for coordinate in emitter.position {
		key = generation_seed.hash_u64(key ~ u64(u32(i32(math.floor(coordinate)))))
	}
	return generation_seed.hash_u64(key ~ u64(emitter.kind))
}

// 1 until the last third of the life, then down to 0.
particle_alpha :: proc(particle: Particle) -> f32 {
	remaining := 1 - particle.age_seconds / particle.life_seconds
	return clamp(remaining / PARTICLE_FADE_SHARE, 0, 1)
}

// From the start size to growth times it over the life.
particle_draw_size :: proc(particle: Particle) -> f32 {
	growth := particle_behaviours[particle.kind].growth
	return particle.size * math.lerp(f32(1), growth, particle.age_seconds / particle.life_seconds)
}
