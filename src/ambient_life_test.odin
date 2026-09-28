package game

import "core:math"
import "core:math/linalg"
import "core:testing"

// Distance from a point in the loop's plane to the loop's inner
// rectangle, which is the corner radius for every point on the loop.
distance_to_loop_inner_rectangle :: proc(point: [2]f32) -> f32 {
	inner := [2]f32{FLOCK_LOOP_LENGTH / 2 - FLOCK_LOOP_CORNER_RADIUS, FLOCK_LOOP_WIDTH / 2 - FLOCK_LOOP_CORNER_RADIUS}
	return linalg.length(point - linalg.clamp(point, -inner, inner))
}

near :: proc(first, second: [2]f32) -> bool {
	return linalg.length(first - second) < 0.001
}

@(test)
test_flock_placement_is_deterministic_and_follows_density :: proc(t: ^testing.T) {
	testing.expect_value(t, flock_cell_hash(7, {3, -4}), flock_cell_hash(7, {3, -4}))
	testing.expect(t, flock_cell_hash(7, {3, -4}) != flock_cell_hash(8, {3, -4}))
	testing.expect(t, flock_cell_hash(7, {3, -4}) != flock_cell_hash(7, {-4, 3}))
	present, total := 0, 0
	for z in i32(-40) ..< 40 {
		for x in i32(-40) ..< 40 {
			hash := flock_cell_hash(DEFAULT_WORLD_SEED, {x, z})
			testing.expect(t, !flock_present(hash, 0))
			testing.expect(t, flock_present(hash, 1))
			present += flock_present(hash, 0.4) ? 1 : 0
			total += 1
			column := flock_centre_column({x, z}, hash)
			centre := [2]i32{x, z} * FLOCK_CELL_SIZE + FLOCK_CELL_SIZE / 2
			testing.expect(t, abs(column.x - centre.x) <= FLOCK_CENTRE_JITTER && abs(column.y - centre.y) <= FLOCK_CENTRE_JITTER)
			flock := make_flock(hash, column, 40)
			testing.expect(t, flock.bird_count >= FLOCK_MINIMUM_BIRDS && flock.bird_count <= FLOCK_MAXIMUM_BIRDS)
			testing.expect(t, abs(flock.period_seconds - FLOCK_PERIOD_SECONDS) <= FLOCK_PERIOD_SECONDS * FLOCK_PERIOD_SPREAD)
		}
	}
	share := f64(present) / f64(total)
	testing.expectf(t, share > 0.37 && share < 0.43, "flock share %v at density 0.4", share)
}

@(test)
test_rounded_rectangle_loop :: proc(t: ^testing.T) {
	testing.expect(t, near(rounded_rectangle_point(0), {-12, -12}))
	testing.expect(t, near(rounded_rectangle_point(0.5), {12, 12}))
	testing.expect(t, near(rounded_rectangle_point(1), rounded_rectangle_point(0)))
	testing.expect(t, near(rounded_rectangle_point(0.75), -rounded_rectangle_point(0.25)))
	quarter := rounded_rectangle_point(0.25)
	testing.expect(t, quarter.x > 0 && quarter.y < 0)
	for step in 0 ..< 400 {
		point := rounded_rectangle_point(f64(step) / 400)
		testing.expectf(t, abs(distance_to_loop_inner_rectangle(point) - FLOCK_LOOP_CORNER_RADIUS) < 0.001, "step %d at %v is off the loop", step, point)
	}
}

// A flock with a known phase: bird 0 at loop phases 0, 0.25 and 0.5
// sits on the loop at that share (less its spacing), within its side
// spread and bob, and the others trail it.
@(test)
test_bird_positions_along_the_loop :: proc(t: ^testing.T) {
	flock := Flock {
		hash           = 12345,
		centre         = {100, 60, -40},
		bird_count     = 7,
		period_seconds = 60,
		direction      = 1,
	}
	for phase in ([3]f64{0, 0.25, 0.5}) {
		loop_seconds := phase * flock.period_seconds
		share := flock_bird_share(flock, 0, loop_seconds)
		testing.expect(t, share <= phase + 1e-9 || share > 0.99)
		testing.expect(t, math.abs(phase - share) < 2 * BIRD_SPACING_SHARE || share > 0.99)
		pose := flock_bird_pose(flock, 0, loop_seconds)
		on_loop := rounded_rectangle_point(share)
		horizontal := [2]f32{pose.position.x - flock.centre.x, pose.position.z - flock.centre.z}
		testing.expect(t, linalg.length(horizontal - on_loop) <= BIRD_SIDE_SPREAD + 0.001)
		testing.expect(t, abs(pose.position.y - flock.centre.y) <= BIRD_BOB_AMPLITUDE + 0.001)
		testing.expect(t, abs(linalg.length(pose.heading) - 1) < 0.001)
		for bird in 1 ..< flock.bird_count {
			ahead := flock_bird_share(flock, bird - 1, loop_seconds)
			behind := flock_bird_share(flock, bird, loop_seconds)
			gap := ahead - behind
			gap -= math.floor(gap)
			testing.expect(t, gap >= 0.5 * BIRD_SPACING_SHARE - 1e-9 && gap <= 1.5 * BIRD_SPACING_SHARE + 1e-9)
		}
	}
	first := flock_bird_pose(flock, 0, 0).position
	half := flock_bird_pose(flock, 0, 0.5 * flock.period_seconds).position
	// Point symmetric loop: half a period later bird 0 is across the centre.
	testing.expect(t, linalg.length((first.xz + half.xz) / 2 - flock.centre.xz) <= BIRD_SIDE_SPREAD + 0.001)
	testing.expect_value(t, flock_bird_pose(flock, 3, 17.5), flock_bird_pose(flock, 3, 17.5))
}

// Every flock the shipped world has around the origin flies above the
// surface sampled at its loop's centre, over a whole period.
@(test)
test_flock_paths_stay_above_the_surface :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	maximum_density := maximum_bird_density(generator.biomes)
	found := 0
	for z in i32(-6) ..= 6 {
		for x in i32(-6) ..= 6 {
			flock, present := find_flock(&generator, DEFAULT_WORLD_SEED, {x, z}, maximum_density)
			if !present {
				continue
			}
			found += 1
			column := flock_centre_column({x, z}, flock.hash)
			surface := f32(sample_column(&generator, column.x, column.y).height)
			for step in 0 ..< 60 {
				for bird in 0 ..< flock.bird_count {
					pose := flock_bird_pose(flock, bird, f64(step) * flock.period_seconds / 60)
					testing.expect(t, pose.position.y >= surface + FLOCK_MINIMUM_ALTITUDE - BIRD_BOB_AMPLITUDE)
					testing.expect(t, pose.position.y <= surface + FLOCK_MAXIMUM_ALTITUDE + BIRD_BOB_AMPLITUDE + 1)
				}
			}
		}
	}
	testing.expectf(t, found > 0, "no flock in 169 cells around the origin")
}

@(test)
test_insect_and_fish_selection_per_cell :: proc(t: ^testing.T) {
	insects, fish, total := 0, 0, 0
	for z in i32(-40) ..< 40 {
		for x in i32(-40) ..< 40 {
			cell := World_Coordinate{x, 32, z}
			insects += flower_has_insects(cell) ? 1 : 0
			fish += fish_in_cell(cell) ? 1 : 0
			total += 1
		}
	}
	insect_share := f64(insects) / f64(total)
	fish_share := f64(fish) / f64(total)
	testing.expectf(t, abs(insect_share - 1.0 / INSECT_FLOWER_SHARE) < 0.03, "insect share %v", insect_share)
	testing.expectf(t, abs(fish_share - 1.0 / FISH_CELL_SHARE) < 0.02, "fish share %v", fish_share)
	cell := World_Coordinate{10, 40, -7}
	testing.expect_value(t, fish_in_cell(cell), fish_in_cell(cell))
	for step in 0 ..< 200 {
		seconds := f64(step) * 0.37
		for mote in 0 ..< INSECT_MOTES_PER_FLOWER {
			position := insect_mote_position(cell, mote, seconds)
			offset := position - {10.5, 40, -6.5}
			testing.expect(t, abs(offset.x) <= INSECT_MAXIMUM_RADIUS && abs(offset.z) <= INSECT_MAXIMUM_RADIUS)
			testing.expect(t, offset.y >= INSECT_HEIGHT - INSECT_VERTICAL_AMPLITUDE - 0.001 && offset.y <= INSECT_HEIGHT + INSECT_VERTICAL_AMPLITUDE + 0.001)
		}
		pose := fish_pose(cell, seconds)
		testing.expect(t, abs(pose.position.x - 10.5) <= FISH_MAXIMUM_AMPLITUDE && abs(pose.position.z + 6.5) <= FISH_MAXIMUM_AMPLITUDE)
		testing.expect_value(t, pose.position.y, f32(41 - FISH_DEPTH))
		testing.expect(t, abs(linalg.length(pose.heading) - 1) < 0.001)
	}
	// Two motes of one flower, and the same mote of two flowers, differ.
	testing.expect(t, insect_mote_position(cell, 0, 3) != insect_mote_position(cell, 1, 3))
	testing.expect(t, insect_mote_position(cell, 0, 3) != insect_mote_position(cell + {1, 0, 0}, 0, 3) - {1, 0, 0})
}

@(test)
test_life_presence_by_day_and_weather :: proc(t: ^testing.T) {
	testing.expect_value(t, life_presence(0, 0), 0)
	testing.expect_value(t, life_presence(1, 0), 1)
	testing.expect_value(t, life_presence(1, 1), 0)
	testing.expect_value(t, life_presence(1, LIFE_RAIN_GROUNDED), 0)
	testing.expect_value(t, fog_fade(10, 96, 160), 1)
	testing.expect_value(t, fog_fade(200, 96, 160), 0)
	for step in 0 ..< 500 {
		lift := bird_wing_lift(99, 2, f64(step) * 0.05)
		testing.expect(t, lift >= -1 && lift <= 1)
	}
	testing.expect_value(t, chunk_distance_squared({10, 10, 10}, {0, 0, 0}), 0)
	testing.expect_value(t, chunk_distance_squared({-3, 0, 0}, {0, 0, 0}), 9)
}
