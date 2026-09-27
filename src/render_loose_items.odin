package game

import "core:math"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

// Loose items (loose_item.odin): one small cube per stack, coloured like
// the items on belts (item_cube_color), turning slowly and bobbing with
// the render time. A falling stack moves smoothly between cells.

LOOSE_ITEM_CUBE_SIZE :: 0.3
LOOSE_ITEM_TURN_SECONDS :: 6.0
LOOSE_ITEM_BOB_SECONDS :: 2.0
LOOSE_ITEM_BOB_HEIGHT :: 0.06

// How far below its cell a stack is drawn: from the state before the
// latest tick (fall_ticks - 1) to the latest one.
loose_item_fall_distance :: proc(fall_ticks: u32, alpha: f32) -> f32 {
	if fall_ticks == 0 {
		return 0
	}
	return min((f32(fall_ticks - 1) + alpha) / LOOSE_ITEM_FALL_TICKS, 1)
}

// The centre of the stack's cube this frame. Stacks in one cell spread
// by their offset; the phase offset keeps neighbours out of step.
loose_item_draw_centre :: proc(loose: Loose_Item, frame: Model_Frame) -> [3]f32 {
	bob_phase := motion_phase(frame.tick, frame.alpha, frame.tick_rate, LOOSE_ITEM_BOB_SECONDS, true, motion_phase_offset(loose.cell))
	bob := LOOSE_ITEM_BOB_HEIGHT * (1 + math.sin(2 * math.PI * bob_phase))
	point := loose_item_point(loose)
	point.y = f32(loose.cell.y) + LOOSE_ITEM_CUBE_SIZE / 2 + bob - loose_item_fall_distance(loose.fall_ticks, frame.alpha)
	return point
}

draw_loose_items :: proc(world: ^World, items: Item_Registry, frame: Model_Frame) {
	for loose in world.entities.loose_items.items {
		centre := loose_item_draw_centre(loose, frame)
		turn := motion_phase(frame.tick, frame.alpha, frame.tick_rate, LOOSE_ITEM_TURN_SECONDS, true, motion_phase_offset(loose.cell))
		rlgl.PushMatrix()
		rlgl.Translatef(centre.x, centre.y, centre.z)
		rlgl.Rotatef(turn * 360, 0, 1, 0)
		rl.DrawCube({}, LOOSE_ITEM_CUBE_SIZE, LOOSE_ITEM_CUBE_SIZE, LOOSE_ITEM_CUBE_SIZE, item_cube_color(items, loose.item))
		rlgl.PopMatrix()
	}
}
