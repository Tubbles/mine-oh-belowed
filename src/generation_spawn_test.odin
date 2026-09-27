package game

import "core:log"
import "core:slice"
import "core:testing"

// Seeds the landing site tests (work item 0045) run on.
LANDING_SITE_TEST_SEEDS :: [7]u64{DEFAULT_WORLD_SEED, 1, 2, 3, 4, 5, 6}

// A test generator with the landing pad on the seed's spawn.
make_landed_test_generator :: proc(t: ^testing.T, seed: u64) -> (generator: Generator, found: bool) {
	generator = make_test_generator(seed)
	spawn: World_Coordinate
	spawn, found = find_spawn(&generator)
	testing.expectf(t, found, "no spawn for seed %d", seed)
	generator.landing_pad = Landing_Pad_Site{present = true, centre = spawn}
	return generator, found
}

pad_distance_squared :: proc(generator: ^Generator, vein: Vein) -> i32 {
	offset := vein.centre - generator.landing_pad.centre
	return offset.x * offset.x + offset.z * offset.z
}

// The vein layer_veins lists with the starter vein's centre.
listed_vein_at :: proc(generator: ^Generator, starter: Vein) -> (listed: Vein, found: bool) {
	region := block_to_region(starter.centre.x, starter.centre.z)
	for vein in region_veins(generator, region, context.temp_allocator) {
		if vein.centre == starter.centre {
			return vein, true
		}
	}
	return {}, false
}

@(test)
test_landing_site_is_flat :: proc(t: ^testing.T) {
	for seed in LANDING_SITE_TEST_SEEDS {
		generator, found := make_landed_test_generator(t, seed)
		if !found {
			continue
		}
		centre := generator.landing_pad.centre
		log.infof("seed %d: spawn %v", seed, centre)
		testing.expectf(t, landing_site_is_flat(&generator, {centre.x, centre.z}), "seed %d spawn %v not flat", seed, centre)
		findings := evaluate_spawn(&generator, {centre.x, centre.z})
		testing.expectf(t, spawn_satisfied(findings), "seed %d findings %v", seed, findings)
	}
}

// One starter vein per spawn type, near the pad, listed by layer_veins as
// an ordinary vein and clear of every other vein of its region.
@(test)
test_starter_veins_near_the_pad :: proc(t: ^testing.T) {
	for seed in LANDING_SITE_TEST_SEEDS {
		generator, found := make_landed_test_generator(t, seed)
		if !found {
			continue
		}
		starters := starter_veins(&generator, context.temp_allocator)
		testing.expectf(t, len(starters) == len(generator.veins.spawn_types), "seed %d has %d starter veins", seed, len(starters))
		for starter, number in starters {
			testing.expect_value(t, starter.type, generator.veins.spawn_types[number])
			testing.expectf(t, pad_distance_squared(&generator, starter) <= STARTER_VEIN_MAXIMUM_DISTANCE * STARTER_VEIN_MAXIMUM_DISTANCE, "seed %d starter %v too far", seed, starter.centre)
			listed, listed_found := listed_vein_at(&generator, starter)
			testing.expectf(t, listed_found, "seed %d starter %v not listed", seed, starter.centre)
			region := region_veins(&generator, listed.id.region, context.temp_allocator)
			for other in region {
				testing.expect(t, other.id == listed.id || !discs_overlap(other.centre, other.radius, listed.centre, listed.radius))
			}
		}
	}
}

// Every footprint column of a starter vein holds its outcrop block with
// only air or water above it.
@(test)
test_starter_outcrops_open_to_the_sky :: proc(t: ^testing.T) {
	for seed in LANDING_SITE_TEST_SEEDS {
		generator, found := make_landed_test_generator(t, seed)
		if !found {
			continue
		}
		cache: map[Chunk_Coordinate]^Chunk
		defer delete(cache)
		for starter in starter_veins(&generator, context.temp_allocator) {
			expect_open_outcrop(t, &generator, &cache, starter)
		}
	}
}

expect_open_outcrop :: proc(t: ^testing.T, generator: ^Generator, cache: ^map[Chunk_Coordinate]^Chunk, vein: Vein) {
	for z in vein.centre.z - vein.radius ..= vein.centre.z + vein.radius {
		for x in vein.centre.x - vein.radius ..= vein.centre.x + vein.radius {
			if !column_in_disc(vein.centre, vein.radius, x, z) {
				continue
			}
			surface := World_Coordinate{x, terrain_height(generator.seeds, x, z), z}
			testing.expect_value(t, cached_block_at(generator, cache, surface), outcrop_block(generator, vein, x, z))
			for y in surface.y + 1 ..= surface.y + CHUNK_SIZE {
				block := cached_block_at(generator, cache, {x, y, z})
				testing.expectf(t, block == AIR_BLOCK || block == generator.blocks.water, "block %d above outcrop %v at height %d", block, surface, y)
			}
		}
	}
}

@(test)
test_landed_generation_is_deterministic :: proc(t: ^testing.T) {
	for seed in LANDING_SITE_TEST_SEEDS {
		generator, found := make_landed_test_generator(t, seed)
		if !found {
			continue
		}
		other_instance := make_test_generator(seed)
		other_instance.landing_pad = generator.landing_pad
		for starter in starter_veins(&generator, context.temp_allocator) {
			coordinate := world_to_chunk_coordinate(starter.centre)
			first := generate_chunk(&generator, coordinate)
			second := generate_chunk(&other_instance, coordinate)
			testing.expectf(t, slice.equal(first.chunk.blocks[:], second.chunk.blocks[:]), "seed %d chunk %v differs between runs", seed, coordinate)
			testing.expect(t, slice.equal(first.veins[:], second.veins[:]))
			testing.expect(t, len(first.outcrops) > 0 && slice.equal(first.outcrops[:], second.outcrops[:]))
			destroy_generated_chunk(first)
			destroy_generated_chunk(second)
		}
	}
}

// generate_chunk grows the outcrop and crate lists inside its temp
// allocator guard, so the determinism test allocates them on the heap.
destroy_generated_chunk :: proc(generated: Generated_Chunk) {
	free(generated.chunk)
	delete(generated.veins)
	delete(generated.outcrops)
	delete(generated.crates)
}
