package game

import "core:testing"

test_particle :: proc(kind: Particle_Kind) -> Particle {
	return Particle{kind = kind, life_seconds = 1, size = 1, color = {255, 255, 255, 255}}
}

// A full pool replaces its oldest particle and keeps its capacity.
@(test)
test_particle_pool_wraps_and_replaces_the_oldest :: proc(t: ^testing.T) {
	system := new(Particle_System, context.temp_allocator)
	for index in 0 ..< PARTICLE_CAPACITY {
		particle := test_particle(.Smoke)
		particle.position.x = f32(index)
		add_particle(system, particle)
	}
	testing.expect_value(t, live_particle_count(system), PARTICLE_CAPACITY)
	testing.expect_value(t, system.next, 0)
	newest := test_particle(.Spark)
	newest.position.x = -1
	add_particle(system, newest)
	testing.expect_value(t, live_particle_count(system), PARTICLE_CAPACITY)
	testing.expect_value(t, system.particles[0].kind, Particle_Kind.Spark)
	testing.expect_value(t, system.particles[1].position.x, 1)
	testing.expect_value(t, system.next, 1)
}

// Debris and sparks fall, smoke and steam rise, and drag slows all of
// them; exhaust keeps less of its sideways speed than smoke.
@(test)
test_particle_advance_applies_gravity_and_drag :: proc(t: ^testing.T) {
	seconds: f32 = 0.05
	for kind in ([?]Particle_Kind{.Debris, .Spark}) {
		testing.expect(t, advance_particle(test_particle(kind), seconds).velocity.y < 0, "falls")
	}
	for kind in ([?]Particle_Kind{.Smoke, .Steam, .Flame, .Exhaust, .Puff}) {
		testing.expect(t, advance_particle(test_particle(kind), seconds).velocity.y > 0, "rises")
	}
	moving := test_particle(.Smoke)
	moving.velocity = {1, 0, 0}
	smoke := advance_particle(moving, seconds)
	testing.expect_value(t, smoke.velocity.x, 1 - particle_behaviours[.Smoke].drag * seconds)
	testing.expect_value(t, smoke.position.x, smoke.velocity.x * seconds)
	moving.kind = .Exhaust
	testing.expect(t, advance_particle(moving, seconds).velocity.x < smoke.velocity.x, "exhaust drags more")
	testing.expect(t, particle_behaviours[.Steam].gravity > particle_behaviours[.Smoke].gravity, "steam rises faster")
}

@(test)
test_particle_retires_at_its_life :: proc(t: ^testing.T) {
	system := new(Particle_System, context.temp_allocator)
	add_particle(system, test_particle(.Smoke))
	advance_particles(system, 0.5)
	testing.expect_value(t, live_particle_count(system), 1)
	testing.expect_value(t, system.particles[0].age_seconds, 0.5)
	advance_particles(system, 0.5)
	testing.expect_value(t, live_particle_count(system), 0)
}

@(test)
test_particle_fades_over_the_last_third :: proc(t: ^testing.T) {
	particle := test_particle(.Smoke)
	testing.expect_value(t, particle_alpha(particle), 1)
	particle.age_seconds = 0.5
	testing.expect_value(t, particle_alpha(particle), 1)
	particle.age_seconds = 0.9
	alpha := particle_alpha(particle)
	testing.expect(t, alpha > 0.29 && alpha < 0.31, "fading")
	size := particle_draw_size(particle)
	expected := 1 + (particle_behaviours[.Smoke].growth - 1) * 0.9
	testing.expect(t, abs(size - expected) < 0.001, "grows over the life")
}

// The same frame and emitter give the same particles; another frame
// gives others. The count holds the rate on average.
@(test)
test_particle_spawning_is_deterministic :: proc(t: ^testing.T) {
	emitter := Emitter{position = {3.5, 10, -2.5}, kind = .Smoke, rate = 30, color = {90, 90, 90, 255}, spread = 0.3}
	first := new(Particle_System, context.temp_allocator)
	second := new(Particle_System, context.temp_allocator)
	spawn_particles(first, emitter, 0.1, emitter_random_key(7, emitter))
	spawn_particles(second, emitter, 0.1, emitter_random_key(7, emitter))
	testing.expect(t, first^ == second^, "same frame, same particles")
	count := live_particle_count(first)
	testing.expect(t, count == 3 || count == 4, "rate times seconds")
	testing.expect(t, emitter_random_key(7, emitter) != emitter_random_key(8, emitter), "frames differ")
	moved := emitter
	moved.position.x += 1
	testing.expect(t, emitter_random_key(7, emitter) != emitter_random_key(7, moved), "cells differ")
	for particle in first.particles[:count] {
		offset := particle.position - emitter.position
		testing.expect(t, offset.x * offset.x + offset.z * offset.z <= emitter.spread * emitter.spread + 0.0001, "inside the spread")
		testing.expect_value(t, particle.color, emitter.color)
	}
	total := 0
	for frame in u64(0) ..< 1000 {
		total += particle_spawn_count(2.5, 0.1, emitter_random_key(frame, emitter))
	}
	testing.expect(t, total > 200 && total < 300, "the rate holds on average")
}
