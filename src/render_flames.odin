package game

import "core:math"
import rl "shared:raylib"
import "shared:raylib/rlgl"

// Torch flames (work item 0061): a small camera facing quad above every
// light emitting post the mesher found (Chunk_Mesh_Data.flames). Its size
// and brightness flicker with the render time, phase shifted by a hash of
// the cell so neighbouring torches do not pulse together. Render only,
// nothing here reaches the simulation. Drawn after the world without depth
// writes, like item billboards.

FLAME_SIZE :: 0.2
FLAME_FLICKER_HERTZ :: 5.0
// The flame's size swings between this share of FLAME_SIZE and the whole.
FLAME_SMALLEST_SHARE :: 0.75
FLAME_DIM_COLOR :: rl.Color{255, 120, 30, 210}
FLAME_BRIGHT_COLOR :: rl.Color{255, 225, 120, 245}

// 0 to 1: two sine waves of unrelated speeds, phase shifted per cell.
flame_flicker :: proc(cell: World_Coordinate, seconds: f64) -> f32 {
	key := u64(u32(cell.x)) ~ (u64(u32(cell.y)) << 21) ~ (u64(u32(cell.z)) << 42)
	phase := f64(hash_u64(key) % 1024) / 1024 * math.TAU
	angle := seconds * FLAME_FLICKER_HERTZ * math.TAU + phase
	wave := 0.6 * math.sin(angle) + 0.4 * math.sin(2.3 * angle + phase)
	return f32(wave * 0.5 + 0.5)
}

// Centred on the post, resting on its top.
flame_centre :: proc(cell: World_Coordinate, size: f32) -> [3]f32 {
	return {f32(cell.x) + 0.5, f32(cell.y) + POST_HEIGHT + size / 2, f32(cell.z) + 0.5}
}

flame_size :: proc(flicker: f32) -> f32 {
	return FLAME_SIZE * (FLAME_SMALLEST_SHARE + (1 - FLAME_SMALLEST_SHARE) * flicker)
}

// Between BeginMode3D and EndMode3D, after everything opaque. The quad
// samples raylib's white default texture, so it takes the flame colour.
draw_torch_flames :: proc(renderer: ^Chunk_Renderer, camera: rl.Camera3D, seconds: f64) {
	white := rl.Texture2D {
		id      = rlgl.GetTextureIdDefault(),
		width   = 1,
		height  = 1,
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	}
	begin_item_billboards()
	defer end_item_billboards()
	for _, chunk_render in renderer.chunk_meshes {
		for cell in chunk_render.flames {
			flicker := flame_flicker(cell, seconds)
			size := flame_size(flicker)
			color := rl.ColorLerp(FLAME_DIM_COLOR, FLAME_BRIGHT_COLOR, flicker)
			rl.DrawBillboardRec(camera, white, {0, 0, 1, 1}, flame_centre(cell, size), {size, size}, color)
		}
	}
}
