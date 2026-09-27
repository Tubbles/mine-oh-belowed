# 0047 Saves that survive additive changes

Status: todo
Milestone: M10

## Goal

Every build since the couch tests began has refused the previous build's saves, because the entities file is a raw field image stamped with a strict layout fingerprint, and the content fingerprint refuses any change to the id tables. The user tests between commits and loses the world each time. Saves must survive additive changes: a field added or removed, an enum value added, an item, machine, recipe, technology, quest or contract added or removed. Only a retyped field refuses.

## Deliverables

- Self describing structs in the codec (`src/save_binary.odin`): a struct is written as its field count, then per field the field name, a shallow kind fingerprint of the field's type (integer size and sign, float size, bool, enum by type name, bit set by its enum's name, array count with element kind, slice element kind, struct by its type name, distinct id types by name), the byte length of the field's encoding, and the encoding itself, recursively. On read, fields are matched by name: a known field with the same kind is read, an unknown field is skipped by its length, a missing field keeps its zero value, and a field whose kind changed refuses the file with a message naming the struct and field. Enums are written by name and read by name, an unknown name giving the zero value; bit sets of enums as the list of set names.
- Content remapping: the entities file carries the id tables at save time (blocks, items, fluids, machines, recipes, technologies, quests, contracts, vein types, as string ids in index order). On load, old index to new index maps are built; values of the distinct id types (`Item_Id`, `Block_Id`, `Fluid_Id`, `Machine_Id`) are remapped inside the codec from their type name, and every array indexed by an id (statistics per item, block and machine, recipe unlocks, research levels and kept units, quest progress, contract offer counts) and every plain integer index (craft queue recipes, assembler recipes, the queued and finished technology, the active quest, open contracts, catalogue orders) is remapped explicitly; list every such place in the notes. An id that vanished becomes the "none" value or is dropped (an item stack becomes empty, a quest's progress is dropped), a new id starts at zero. Chunk block ids in the region files are remapped through the block table when a chunk loads, so the block map lives on the session's save state. Anything that cannot be remapped safely refuses the file with a clear message rather than loading it wrong.
- The format version becomes 2. Version 1 files are refused with the existing message. The layout fingerprint leaves the header (the content fingerprint too, replaced by the tables); `header_problem` and the load list's marker follow.
- Tests: round trip unchanged; a struct with a field added, one removed and the order changed between write and read (test structs) loads with the shared fields intact; an enum value renamed reads as zero and an added one round trips; content change tests over the save test's world: an item inserted at the front of the registry keeps every inventory, chest, belt and statistic on its item, a removed item empties its stacks, a recipe inserted keeps craft queues and assembler recipes, a technology inserted keeps research levels and the queued technology, a quest inserted keeps the active quest and progress, a contract removed drops its open slot; a block inserted keeps every chunk's blocks after load.

## Verify

- Builds and tests pass.
- User: save with one build, then load with the next after a field, a quest and an item were added, and keep playing.
