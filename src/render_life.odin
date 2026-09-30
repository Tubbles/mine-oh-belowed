package game

import "core:math"
import "core:math/linalg"
import rl "shared:raylib"
import "shared:raylib/rlgl"

// Drawing of ambient life (work item 0075, pure parts in
// ambient_life.odin): bird flocks as dark silhouettes of a body and two
// wings, insect motes as small bright billboards, fish shadows as dark
// ellipses under the water surface. Nothing is kept between frames; the
// flocks are found anew from the seed and the camera every frame, the
// motes and fish from the chunk renders' covers and fish lists
// (render_chunks.odin).

BIRD_COLOR :: rl.Color{38, 36, 42, 255}
BIRD_BODY_LENGTH :: 0.5
BIRD_BODY_WIDTH :: 0.12
BIRD_WING_SPAN :: 1.1
BIRD_WING_CHORD :: 0.16
// How far the wing tips rise and fall at a full beat.
BIRD_WING_TIP_TRAVEL :: 0.3
INSECT_MOTE_COLOR :: rl.Color{250, 238, 170, 230}
INSECT_MOTE_SIZE :: 0.07
FISH_COLOR :: rl.Color{12, 22, 28, 130}
FISH_ELLIPSE_SEGMENTS :: 10

// What one frame of ambient life depends on. loop_seconds is the tick
// (with the interpolation alpha) in seconds, seconds the render time.
// presence is life_presence, light the sky light factor (day_factor).
Life_Frame :: struct {
	camera:       rl.Camera3D,
	seed:         u64,
	loop_seconds: f64,
	seconds:      f64,
	presence:     f32,
	light:        f32,
	fog_start:    f32,
	fog_end:      f32,
}

// A plant's world cell and block, from the mesher's covers.
Life_Cover :: struct {
	cell:  World_Coordinate,
	block: Block_Id,
}

life_color :: proc(color: rl.Color, share: f32) -> rl.Color {
	faded := color
	faded.a = u8(f32(color.a) * clamp(share, 0, 1))
	return faded
}

// Two triangles, drawn within begin_translucent_pass and end_translucent_pass.
draw_life_quad :: proc(corners: [4][3]f32, color: rl.Color) {
	rl.DrawTriangle3D(corners[0], corners[1], corners[2], color)
	rl.DrawTriangle3D(corners[0], corners[2], corners[3], color)
}

// The body along the heading and each wing from the body's middle out to
// a tip raised or lowered by lift (-1 to 1).
draw_bird :: proc(pose: Bird_Pose, lift: f32, color: rl.Color) {
	forward := pose.heading
	side := [3]f32{-forward.z, 0, forward.x}
	centre := pose.position
	body_half := forward * (BIRD_BODY_LENGTH / 2)
	body_side := side * (BIRD_BODY_WIDTH / 2)
	draw_life_quad({centre - body_half - body_side, centre + body_half - body_side, centre + body_half + body_side, centre - body_half + body_side}, color)
	chord := forward * (BIRD_WING_CHORD / 2)
	tip_rise := [3]f32{0, lift * BIRD_WING_TIP_TRAVEL, 0}
	signs := [2]f32{-1, 1}
	for sign in signs {
		tip := centre + side * (sign * BIRD_WING_SPAN / 2) + tip_rise
		draw_life_quad({centre - chord, centre + chord, tip + chord * 0.5, tip - chord * 0.5}, color)
	}
}

// The flock at a cell, if its biome's density lets it fly there.
find_flock :: proc(generator: ^Generator, seed: u64, cell: [2]i32, maximum_density: f32) -> (flock: Flock, found: bool) {
	hash := flock_cell_hash(seed, cell)
	// Most cells fail here, before their column is sampled.
	if !flock_present(hash, maximum_density) {
		return {}, false
	}
	column := flock_centre_column(cell, hash)
	sample := sample_column(generator, column.x, column.y)
	if sample.biome >= len(generator.biomes) || !flock_present(hash, generator.biomes[sample.biome].definition.bird_density) {
		return {}, false
	}
	return make_flock(hash, column, sample.height), true
}

draw_flock :: proc(flock: Flock, frame: Life_Frame) {
	for bird in 0 ..< flock.bird_count {
		pose := flock_bird_pose(flock, bird, frame.loop_seconds)
		distance := linalg.length(pose.position - frame.camera.position)
		if distance > BIRD_DRAW_DISTANCE {
			continue
		}
		color := life_color(BIRD_COLOR, frame.presence * fog_fade(distance, frame.fog_start, frame.fog_end))
		draw_bird(pose, bird_wing_lift(flock.hash, bird, frame.seconds), color)
	}
}

// The flocks within BIRD_DRAW_DISTANCE, by day and not in rain. Between
// BeginMode3D and EndMode3D, after the world.
draw_bird_flocks :: proc(generator: ^Generator, frame: Life_Frame) {
	maximum_density := maximum_bird_density(generator.biomes)
	if frame.presence <= 0 || maximum_density <= 0 {
		return
	}
	minimum, maximum := flock_cells_around(frame.camera.position.xz, BIRD_DRAW_DISTANCE)
	begin_translucent_pass()
	defer end_translucent_pass()
	for z in minimum.y ..= maximum.y {
		for x in minimum.x ..= maximum.x {
			if flock, found := find_flock(generator, frame.seed, {x, z}, maximum_density); found {
				draw_flock(flock, frame)
			}
		}
	}
}

life_white_texture :: proc() -> rl.Texture2D {
	return rl.Texture2D{id = rlgl.GetTextureIdDefault(), width = 1, height = 1, mipmaps = 1, format = .UNCOMPRESSED_R8G8B8A8}
}

// Two motes around every flower that has insects (flower_has_insects)
// within INSECT_DRAW_DISTANCE, by day. Between BeginMode3D and EndMode3D.
draw_insect_motes :: proc(renderer: ^Chunk_Renderer, biomes: []Biome, frame: Life_Frame) {
	if frame.presence <= 0 {
		return
	}
	white := life_white_texture()
	position := frame.camera.position
	begin_item_billboards()
	defer end_item_billboards()
	for coordinate, chunk_render in renderer.chunk_meshes {
		if len(chunk_render.covers) == 0 || chunk_distance_squared(position, coordinate) > INSECT_DRAW_DISTANCE * INSECT_DRAW_DISTANCE {
			continue
		}
		for cover in chunk_render.covers {
			centre := [3]f32{f32(cover.cell.x), f32(cover.cell.y), f32(cover.cell.z)} + 0.5
			distance := linalg.length(centre - position)
			if distance > INSECT_DRAW_DISTANCE || !flower_has_insects(cover.cell) || !block_draws_insects(biomes, cover.block) {
				continue
			}
			color := life_color(INSECT_MOTE_COLOR, frame.presence * fog_fade(distance, frame.fog_start, frame.fog_end))
			for mote in 0 ..< INSECT_MOTES_PER_FLOWER {
				rl.DrawBillboardRec(frame.camera, white, {0, 0, 1, 1}, insect_mote_position(cover.cell, mote, frame.seconds), {INSECT_MOTE_SIZE, INSECT_MOTE_SIZE}, color)
			}
		}
	}
}

// A point of the shadow's outline, segment 0 at its nose.
fish_outline_point :: proc(pose: Fish_Pose, segment: int) -> [3]f32 {
	forward := [3]f32{pose.heading.x, 0, pose.heading.y}
	side := [3]f32{-forward.z, 0, forward.x}
	angle := f32(segment) / FISH_ELLIPSE_SEGMENTS * math.TAU
	return pose.position + forward * (math.cos(angle) * FISH_LENGTH / 2) + side * (math.sin(angle) * FISH_WIDTH / 2)
}

// A flat ellipse along the heading, as a fan of triangles.
draw_fish_shadow :: proc(pose: Fish_Pose, color: rl.Color) {
	for segment in 0 ..< FISH_ELLIPSE_SEGMENTS {
		rl.DrawTriangle3D(pose.position, fish_outline_point(pose, segment), fish_outline_point(pose, segment + 1), color)
	}
}

// The fish shadows within FISH_DRAW_DISTANCE, dimmed at night. Between
// BeginMode3D and EndMode3D, before the water pass, so the surface drawn
// over them tints them.
draw_fish_shadows :: proc(renderer: ^Chunk_Renderer, frame: Life_Frame) {
	position := frame.camera.position
	begin_translucent_pass()
	defer end_translucent_pass()
	for coordinate, chunk_render in renderer.chunk_meshes {
		if len(chunk_render.fish) == 0 || chunk_distance_squared(position, coordinate) > FISH_DRAW_DISTANCE * FISH_DRAW_DISTANCE {
			continue
		}
		for cell in chunk_render.fish {
			pose := fish_pose(cell, frame.seconds)
			distance := linalg.length(pose.position - position)
			if distance > FISH_DRAW_DISTANCE {
				continue
			}
			draw_fish_shadow(pose, life_color(FISH_COLOR, frame.light * fog_fade(distance, frame.fog_start, frame.fog_end)))
		}
	}
}
