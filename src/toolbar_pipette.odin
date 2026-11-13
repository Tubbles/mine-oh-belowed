package game

// The pipette (work item 0216, doc/hud.md, Toolbars): what a tap of
// Pipette's control picks and where on the active toolbar it goes, read
// by the ticks and by the HUD's hint alike. A tick action on the Pipette
// press in the input record, no command.

// The aimed thing's item kind: an aimed cable's (the cable table's index,
// -1 for none) before what lies behind it, else the aimed entity's
// machine's item (aimed_entity). NO_ITEM for nothing aimed and for what
// the world placed (field_entity_is_placed_by_world).
pipette_aimed_item :: proc(entities: ^Entities, machines: Machine_Registry, block_target: Entity_Handle, frame_target: Frame_Raycast_Hit, aimed_cable: int) -> Item_Id {
	if index_in_range(aimed_cable, len(entities.cables.cables)) {
		return entities.cables.cables[aimed_cable].item
	}
	handle := aimed_entity(block_target, frame_target)
	if field_entity_is_placed_by_world(entities, machines, handle) {
		return NO_ITEM
	}
	return machines.machines[entity_common(entities, handle).machine].item
}

// The slot the pipette selects: the selected one when it names the item,
// else the lowest naming it; -1 for none.
pipette_slot :: proc(toolbar: Toolbar, selected: int, item: Item_Id) -> int {
	if toolbar[selected] == item {
		return selected
	}
	for slot, index in toolbar {
		if slot == item {
			return index
		}
	}
	return -1
}

// Selects the active toolbar's slot naming the item, or names it on the
// selected slot when none does, whatever the inventory holds. Nothing for
// NO_ITEM.
apply_pipette :: proc(player: ^Player, item: Item_Id) {
	if item == NO_ITEM {
		return
	}
	if slot := pipette_slot(player.toolbars[player.active_toolbar], player.selected_hotbar_slot, item); slot >= 0 {
		player.selected_hotbar_slot = slot
		return
	}
	player.toolbars[player.active_toolbar][player.selected_hotbar_slot] = item
}
