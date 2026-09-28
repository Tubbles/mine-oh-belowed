package game

import "core:testing"

TEST_TREE_ROOT :: World_Coordinate{0, 0, 0}
// Long enough for any crown to decay to the end.
LEAF_DECAY_TEST_TICKS :: 60 * 60

make_test_tree_felling :: proc(generator: ^Generator, items: Item_Registry) -> Tree_Felling {
	sapling, _ := find_item_id(items, generator.sapling_item)
	return Tree_Felling{blocks = generator.tree_blocks, items = items, sapling = sapling}
}

// The tree's logs, then its leaves where the cell is still air, as
// generation places them.
place_test_tree :: proc(world: ^World, generator: ^Generator, tree: Tree) {
	species := generator.species[tree.species]
	box := tree_box(tree)
	for y in box.minimum.y ..= box.maximum.y {
		for z in box.minimum.z ..= box.maximum.z {
			for x in box.minimum.x ..= box.maximum.x {
				if tree_log_contains(tree, {x, y, z}) {
					world_set_block(world, {x, y, z}, species.log_block)
				}
			}
		}
	}
	for y in box.minimum.y ..= box.maximum.y {
		for z in box.minimum.z ..= box.maximum.z {
			for x in box.minimum.x ..= box.maximum.x {
				if tree.crown != .None && tree_leaves_contain(tree, {x, y, z}) && world_get_block(world, {x, y, z}) == AIR_BLOCK {
					world_set_block(world, {x, y, z}, species.leaves_block)
				}
			}
		}
	}
}

count_tree_blocks_in_box :: proc(world: ^World, blocks: Tree_Blocks, box: Block_Box) -> (logs, leaves: int) {
	for y in box.minimum.y ..= box.maximum.y {
		for z in box.minimum.z ..= box.maximum.z {
			for x in box.minimum.x ..= box.maximum.x {
				block := world_get_block(world, {x, y, z})
				logs += block_is_tree_log(blocks, block) ? 1 : 0
				leaves += block_is_tree_leaves(blocks, block) ? 1 : 0
			}
		}
	}
	return
}

// Long enough for loose items to fall to the ground.
LOOSE_ITEM_SETTLE_TICKS :: 120

// Runs the world and the loose items until the decay queue is empty and
// the items had time to land, or for ticks at most.
run_test_decay :: proc(world: ^World, content: Simulation_Content, felling: Tree_Felling, ticks: int) {
	for tick in 1 ..= ticks {
		tick_world(world, content.blocks, u64(tick), felling)
		tick_entities(world, content, TEST_TICK_RATE)
		if tick >= LOOSE_ITEM_SETTLE_TICKS && len(world.leaf_decay.updates) == 0 && len(world.leaf_decay.felled) == 0 {
			return
		}
	}
}

// Felling the lowest log of every crowned species, the tallest of each
// and so with roots where the species has them, leaves no trunk log and,
// once the decay has run, no leaves: only the roots, and the logs as
// loose items on the ground.
@(test)
test_felling_leaves_no_floating_blocks :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	content := make_test_content()
	content.generator = &generator
	felling := make_test_tree_felling(&generator, content.items)
	for species in generator.species {
		tree := make_test_tree(&generator, species.definition.id, species.definition.maximum_trunk_height)
		tree.root = TEST_TREE_ROOT
		expect_felled_tree_gone(t, content, felling, &generator, tree)
	}
}

expect_felled_tree_gone :: proc(t: ^testing.T, content: Simulation_Content, felling: Tree_Felling, generator: ^Generator, tree: Tree) {
	world := make_loose_item_test_world(content)
	defer destroy_leaf_decay(&world.leaf_decay)
	place_test_tree(&world, generator, tree)
	box := tree_box(tree)
	logs_before, leaves_before := count_tree_blocks_in_box(&world, felling.blocks, box)
	roots := card(tree.root_directions)
	testing.expect_value(t, logs_before, int(tree.trunk_height) + roots)
	testing.expect_value(t, leaves_before > 0, tree.crown != .None)
	lowest := tree.root + {0, 1, 0}
	world_set_block(&world, lowest, AIR_BLOCK)
	fell_tree(&world, content.blocks, felling, lowest)
	logs_after, _ := count_tree_blocks_in_box(&world, felling.blocks, box)
	testing.expectf(t, logs_after == roots, "species %d: %d logs left, %d roots", tree.species, logs_after, roots)
	run_test_decay(&world, content, felling, LEAF_DECAY_TEST_TICKS)
	_, leaves_left := count_tree_blocks_in_box(&world, felling.blocks, box)
	testing.expectf(t, leaves_left == 0, "species %d: %d of %d leaves left", tree.species, leaves_left, leaves_before)
	testing.expect_value(t, len(world.leaf_decay.scheduled), 0)
	log_item := test_item(content.items, "log")
	fallen_logs := 0
	for loose in world.entities.loose_items.items {
		if loose.item == log_item {
			fallen_logs += int(loose.count)
			testing.expectf(t, loose.cell.y == 1, "log item at %v is not on the ground", loose.cell)
		}
	}
	testing.expect_value(t, fallen_logs, int(tree.trunk_height) - 1)
}

// A leaf with a log within LEAF_SUPPORT_DISTANCE stays, one without
// decays, and a leaf nothing scheduled stays whatever its support.
@(test)
test_supported_leaves_survive_decay :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	content := make_test_content()
	content.generator = &generator
	felling := make_test_tree_felling(&generator, content.items)
	world := make_loose_item_test_world(content)
	defer destroy_leaf_decay(&world.leaf_decay)
	registry := content.blocks
	leaves := test_block(registry, "leaves")
	world_set_block(&world, {0, 5, 0}, leaves)
	world_set_block(&world, {2, 3, 0}, test_block(registry, "birch_log"))
	world_set_block(&world, {10, 5, 10}, leaves)
	world_set_block(&world, {-10, 5, -10}, leaves)
	schedule_leaf_decay(&world.leaf_decay, {0, 5, 0}, 5)
	schedule_leaf_decay(&world.leaf_decay, {10, 5, 10}, 5)
	run_test_decay(&world, content, felling, 20)
	testing.expect_value(t, world_get_block(&world, {0, 5, 0}), leaves)
	testing.expect_value(t, world_get_block(&world, {10, 5, 10}), AIR_BLOCK)
	testing.expect_value(t, world_get_block(&world, {-10, 5, -10}), leaves)
	// Six blocks away the log no longer holds the leaf.
	world_set_block(&world, {2, 3, 0}, AIR_BLOCK)
	world_set_block(&world, {3, 2, 0}, test_block(registry, "birch_log"))
	schedule_leaf_decay(&world.leaf_decay, {0, 5, 0}, 30)
	run_test_decay(&world, content, felling, 40)
	testing.expect_value(t, world_get_block(&world, {0, 5, 0}), AIR_BLOCK)
}

// Updates wait for their due tick, at most the bound run per tick, in the
// order queued, and each cell is queued once.
@(test)
test_leaf_decay_queue_order_and_bound :: proc(t: ^testing.T) {
	decay: Leaf_Decay
	defer destroy_leaf_decay(&decay)
	schedule_leaf_decay(&decay, {1, 0, 0}, 10)
	schedule_leaf_decay(&decay, {2, 0, 0}, 5)
	schedule_leaf_decay(&decay, {3, 0, 0}, 5)
	schedule_leaf_decay(&decay, {2, 0, 0}, 1)
	testing.expect_value(t, len(decay.updates), 3)
	testing.expect_value(t, len(take_due_leaf_decays(&decay, 4, 8)), 0)
	due := take_due_leaf_decays(&decay, 5, 1)
	testing.expect_value(t, len(due), 1)
	testing.expect_value(t, due[0], World_Coordinate{2, 0, 0})
	due = take_due_leaf_decays(&decay, 10, 8)
	testing.expect_value(t, len(due), 2)
	testing.expect_value(t, due[0], World_Coordinate{1, 0, 0})
	testing.expect_value(t, due[1], World_Coordinate{3, 0, 0})
	testing.expect_value(t, len(decay.updates), 0)
}

@(test)
test_leaf_decay_delay_and_drops :: proc(t: ^testing.T) {
	litter_count, sapling_count := 0, 0
	for index in u64(0) ..< 8000 {
		hash := leaf_decay_hash({i32(index), 3, -i32(index)}, index)
		delay := leaf_decay_delay(hash)
		testing.expect(t, delay >= LEAF_DECAY_MINIMUM_DELAY_TICKS && delay <= LEAF_DECAY_MAXIMUM_DELAY_TICKS)
		litter, sapling := leaf_litter_drops(hash)
		litter_count += litter ? 1 : 0
		sapling_count += sapling ? 1 : 0
	}
	testing.expect(t, litter_count > 800 && litter_count < 1200, "about one leaf in eight drops litter")
	testing.expect(t, sapling_count > 300 && sapling_count < 500, "about one leaf in twenty drops a sapling")
	testing.expect_value(t, leaf_decay_hash({1, 2, 3}, 7), leaf_decay_hash({1, 2, 3}, 7))
	testing.expect(t, leaf_decay_hash({1, 2, 3}, 7) != leaf_decay_hash({1, 2, 3}, 8))
}

// Without a generator the simulation fells nothing.
@(test)
test_felling_needs_the_generator :: proc(t: ^testing.T) {
	content := make_test_content()
	testing.expect_value(t, len(simulation_tree_felling(content).blocks.logs), 0)
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	content.generator = &generator
	felling := simulation_tree_felling(content)
	testing.expect_value(t, len(felling.blocks.logs), SHIPPED_TREE_SPECIES_COUNT)
	testing.expect_value(t, felling.sapling, test_item(content.items, "sapling"))
}
