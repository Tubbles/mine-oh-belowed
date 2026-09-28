package game

// Ore discovery (work item 0052). A block flagged discoverable in
// blocks.sjson reads "Unknown ore" under the crosshair until its drop item
// has been obtained once (Recipe_Unlocks.obtained, saved with the world).
// The tick that first sees such an item logs "{name} discovered!" through
// the quest message log, so it shows as a toast and in the journal.
// Starting items are obtained while the world is made, before any tick,
// and unlocking everything marks every item obtained, so neither is
// announced. A vein type reads "Unknown ore" until one of its outputs
// that some discoverable block drops is obtained; a type without such an
// output (a quarry, the deep bauxite vein) is always named.

ITEM_DISCOVERED_KEY :: "item_discovered"
UNKNOWN_ORE_KEY :: "block_unknown_ore"

// Whether the item is the drop of a discoverable block.
item_is_discoverable :: proc(blocks: Block_Registry, items: Item_Registry, item: Item_Id) -> bool {
	for drop, block in items.drop_for_block {
		if drop == item && block_is_discoverable(blocks, Block_Id(block)) {
			return true
		}
	}
	return false
}

item_is_obtained :: proc(obtained: []bool, item: Item_Id) -> bool {
	return int(item) < len(obtained) && obtained[item]
}

block_is_discovered :: proc(blocks: Block_Registry, items: Item_Registry, obtained: []bool, block: Block_Id) -> bool {
	return !block_is_discoverable(blocks, block) || item_is_obtained(obtained, block_drop(items, block))
}

// The block's name, or "Unknown ore" for an ore not discovered yet.
target_block_name :: proc(blocks: Block_Registry, items: Item_Registry, obtained: []bool, block: Block_Id) -> string {
	if !block_is_discovered(blocks, items, obtained, block) {
		return text(UNKNOWN_ORE_KEY)
	}
	return block_display_name(blocks, block)
}

vein_type_is_discovered :: proc(vein_type: Vein_Type_Content, blocks: Block_Registry, items: Item_Registry, obtained: []bool) -> bool {
	has_discoverable_output := false
	outputs := vein_type.outputs
	for output in outputs[:vein_type.output_count] {
		if !item_is_discoverable(blocks, items, output) {
			continue
		}
		if item_is_obtained(obtained, output) {
			return true
		}
		has_discoverable_output = true
	}
	return !has_discoverable_output
}

// One message per newly obtained item that a discoverable block drops.
log_discoveries :: proc(state: ^Quest_State, blocks: Block_Registry, items: Item_Registry, newly_obtained: []Item_Id, tick: u64) {
	for item in newly_obtained {
		if item_is_discoverable(blocks, items, item) {
			log_message(state, Quest_Message{tick = tick, text_key = ITEM_DISCOVERED_KEY, argument_key = items.items[item].name_key, item = item})
		}
	}
}
