package game

import "core:slice"
import "core:testing"

// Work item 0347: the foundations' bricks, without GL.

// A pad of 34 by 2 cells from x -1 to 32 with a stone cutting table (the
// foundations' pool, not a foundation) and a chest on it, and a pad of one
// cell 50 m away on a frame of its own.
lay_test_brick_pads :: proc(t: ^testing.T, entities: ^Entities, machines: Machine_Registry) -> (pad, far: Frame) {
	pad = lay_test_pad(entities, machines, 0, 0, {-1, 0, 0}, {32, 0, 1})
	for stand in ([2]struct {
			machine: string,
			cell:    World_Coordinate,
		}{{"stone_cutting_table", {2, 1, 0}}, {"wooden_chest", {5, 1, 0}}}) {
		_, refusal := place_on_frame(entities, machines, test_machine(machines, stand.machine), pad.id, stand.cell, 0)
		testing.expectf(t, refusal == .None, "%s placed: %v", stand.machine, refusal)
	}
	far = lay_test_pad(entities, machines, 50, 0, {0, 0, 0}, {0, 0, 0})
	testing.expect(t, far.id != pad.id, "the far pad starts a frame")
	return pad, far
}

@(test)
test_foundation_bricks_group_the_cells_by_frame_and_brick :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	pad, far := lay_test_brick_pads(t, &entities, machines)
	cells, bricks, instances := build_foundation_bricks(&entities, machines)
	testing.expect_value(t, len(instances), 69)
	testing.expect_value(t, len(cells), 69)
	expected := [4]struct {
		frame: Frame_Id,
		brick: [3]i32,
		count: int,
	}{{pad.id, {-1, 0, 0}, 2}, {pad.id, {0, 0, 0}, 64}, {pad.id, {1, 0, 0}, 2}, {far.id, {0, 0, 0}, 1}}
	testing.expect_value(t, len(bricks), 4)
	first := 0
	for brick, index in bricks {
		if index >= len(expected) {
			break
		}
		wanted := expected[index]
		testing.expectf(t, brick.frame == wanted.frame && brick.brick == wanted.brick && brick.count == wanted.count && brick.first == first, "brick %d: %v", index, brick)
		first += brick.count
	}
	if len(bricks) > 1 {
		testing.expect_value(t, bricks[1].minimum, [3]f32{0, 0, 0})
		testing.expect_value(t, bricks[1].maximum, [3]f32{32, 1, 2})
	}
	testing.expect(t, slice.is_sorted_by(cells, foundation_cell_before), "the cells in foundation_cell_before's order")
	color := foundation_slab_color(machines.machines[test_foundation(machines)])
	for cell, index in cells {
		testing.expectf(t, cell.cell.y == 0, "cell %v: no instance for the table's or the chest's cells", cell.cell)
		instance := instances[index]
		centre := [3]f32{f32(cell.cell.x) + 0.5, f32(cell.cell.y) + 0.5, f32(cell.cell.z) + 0.5}
		testing.expectf(t, instance[0, 3] == centre.x && instance[1, 3] == centre.y && instance[2, 3] == centre.z, "cell %v's centre", cell.cell)
		testing.expectf(t, instance[0, 0] == FRAME_CELL_FILL && instance[1, 1] == FRAME_CELL_FILL && instance[2, 2] == FRAME_CELL_FILL, "cell %v's scale", cell.cell)
		testing.expectf(t, instance[3, 0] == f32(color.r) / 255 && instance[3, 1] == f32(color.g) / 255 && instance[3, 2] == f32(color.b) / 255 && instance[3, 3] == 1, "cell %v's colour", cell.cell)
	}
}

@(test)
test_the_foundation_cache_rebuilds_only_on_a_change :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	pad, _ := lay_test_brick_pads(t, &entities, machines)
	foundations: Field_Foundations
	defer release_field_foundations(&foundations)
	testing.expect(t, refresh_field_foundations(&foundations, &entities, machines, 1), "the first build is a change")
	testing.expect(t, !refresh_field_foundations(&foundations, &entities, machines, 1), "a second is not")
	revision := entities.frames.revision
	set_frame_pose(&entities.frames, pad.id, pad.origin + {POSITION_UNITS_PER_METRE, 0, 0}, pad.axes)
	testing.expect(t, entities.frames.revision != revision, "the pose moves the revision")
	testing.expect(t, !refresh_field_foundations(&foundations, &entities, machines, 1), "a moved pose is not a change")
	testing.expect(t, remove_entity(&entities, machines, entity_at(&entities, {32, 0, 1}, pad.id)), "a corner vacated")
	_, refusal := place_on_frame(&entities, machines, test_foundation(machines), pad.id, {33, 0, 0}, 0)
	testing.expect_value(t, refusal, Frame_Placement_Refusal.None)
	testing.expect(t, refresh_field_foundations(&foundations, &entities, machines, 1), "a cell vacated and another occupied is a change")
	testing.expect(t, !refresh_field_foundations(&foundations, &entities, machines, 2), "the models' revision moved over the same machines is not")
	machines.machines[test_foundation(machines)].color = {1, 2, 3}
	testing.expect(t, refresh_field_foundations(&foundations, &entities, machines, 3), "a new colour with the revision moved is")
	testing.expect(t, !foundations.uploaded, "a change asks for an upload")
}
