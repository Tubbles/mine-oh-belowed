# 0047 Saves that survive additive changes

Status: implemented
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

## Notes

Implementation notes from the subagent run (2026-09-27). Verified headless only: `odin check src -vet -strict-style`, `./build.sh test` (596 tests), `./build.sh`, `./build.sh release`, and a new world `--seed=1 --name=save-test-2` then `--load=save-test-2`, both reaching "could not open a window" (save deleted afterwards).

### Format

- `SAVE_FORMAT_VERSION` 2. `entities.bin`: magic, u32 version, the content tables (u32 byte length, u16 table count, per table its name, a u32 count and the ids), then the state. Region files: magic, u32 version. The layout and content fingerprints are gone with `save_layout_fingerprint`, `content_fingerprint`, `hash_id_list` and `layout_fingerprint`.
- Structs (`src/save_binary.odin`): a schema (u16 field count, per field name, shallow kind u64, fixed encoding size u32 or 0) then a body (per field its encoding, a u32 length first when the size is not fixed). Arrays, slices and lists of structs write the schema once and one body per element. Arrays as a u32 count and their elements. Enums by name, bit sets of an enum as a u16 count and names, enumerated arrays as a u16 count and per element the index name, a u32 length and the element.
- Shallow kinds: integers (size, sign), floats (size), bool, enums by type name, bit sets of an enum by the enum's name and size (others by range and size), arrays by element kind only, enumerated arrays by index enum name and element kind, slices by element kind, structs by type name, other named types (ids, coordinates) by name and base kind. The top level struct written is in no kind, so the tests write one type and read another of a different name honestly.
- Size: the save test's `entities.bin` is 300 478 bytes, 261 kB before.

### Remapped places

Through the codec (distinct ids): every `Item_Stack` (chests, furnaces, capsule, inserters and their held stack, drills and their held stack, fluid machines, assemblers, labs with their packs, schematic crates, launch pads, player inventories, held stacks, pending rewards), inserter and splitter filters, belt cell items, `Shipped_Item`, `Fluid_Buffer` fluids, saved network fluids, `Entity_Common.machine`, `Block_Change.previous`, `Core_Sample.bands`, `Surface_Cell.block`, `Mining_State.block_id`. A stack of a gone item empties, a buffer of a gone fluid drains, a gone block reads as air.

Explicitly (`src/save_remap.odin`): statistics per item (produced, obtained, delivered, voided, consumed, shipped, blocks_placed, held_totals, capsule_totals, the produced and consumed rings), per machine (placed), per block (mining_ticks), per fluid (produced, consumed, voided and their three rings); recipe unlocks (obtained per item, researched per technology, quest_unlocked, schematics_found and available per recipe, then availability recomputed); research (queued and finished technology, units_kept and levels); quest progress per quest and the active quest; open contracts and offer_counts; catalogue order entries (catalogue entries keyed by item and count or `orbital_survey`); furnace and assembler recipes; hand craft queues; vein types of veins, assayed veins and core samples; chunk palettes in region files.

Dropped on a gone id: belt items, shipment cargo entries, pending rewards, craft queue entries (their ingredients are lost), catalogue orders, open contracts (slot freed), assayed veins; a core sample forgets its vein; a furnace stops; an assembler loses its recipe and its recipe slots (`set_assembler_recipe`); a queued technology dequeues; a gone active quest, or all saved quests done while this build added quests, activates the first quest not done.

### Refusals

- A retyped field: `<path> cannot be loaded: the field <field> of <struct> changed its type`.
- A placed entity of a gone machine: `... the save has placed <machine> machines, which this build's game data no longer has`.
- A registered vein of a gone vein type: `... the save has veins of type <id>, ...`.
- A saved chunk holding a gone block: `<region file> cannot be loaded: a saved chunk holds the block <id>, which this build's game data no longer has`.
- Version 1 files: the existing version messages. The load list now lists a save whose `world.sjson` has another version as not loadable (before, it was left out) and checks that the entities file's tables parse.

### Deviations

- Schema hoisting: the brief wrote the name, kind and length per field of every struct value. Arrays of small structs (the explored map is 1024 `Surface_Cell` per column) would have grown about twelvefold, so containers write the schema once and fixed size fields carry no length.
- Enumerated arrays are written by index name, so an enum gaining a value (`Machine_Stall` for `stalls`) does not change the kind.
- Chunk blocks are remapped in the palettes when the region files load (every chunk is decoded there already for validation), not when a chunk streams in. The saved chunks then hold this build's ids, so chunks never loaded are saved again correctly and no block map has to live on the session.
- `Vein_Type_Content` gained `id`; the vein type table uses it instead of `name_key`.

### Array counts

An array's count is not in its kind; the saved count is written before the elements (inside the value, so nested arrays and arrays in slices carry theirs too), and the schema's fixed size is taken from the file. A saved count up to this build's reads the saved elements and zeroes the rest, so raising a `MAXIMUM_*` constant keeps saves loading. A larger saved count refuses: `the field <field> of <struct> holds <saved> saved elements, this build's array has <current>` (arrays outside a struct field: `an array holds ...`). Test: `test_array_counts_may_grow_but_not_shrink`. The save test's `entities.bin` grew by the count per array value.

### Not covered

- Slices of fixed length (player inventory) still refuse on a length change as malformed.
- Vein size classes (`Vein.size_class`, `Assayed_Vein.size_class`) are saved by index, not remapped by id.
- Quest progress arrays indexed by a quest's hints and objectives (`hint_baselines`, `delivered_baselines`, `activation_baselines`, `sustained_ticks`, `sustain_actions`, `hints_fired`) and open contracts' `delivered`, indexed by the contract's requests, follow the index: reordering a quest's hints or objectives or a contract's requests misassigns them.
- Hand craft queue entries of a vanished recipe are removed and the ingredients taken when they were queued are lost.
- A new slice indexed by an id in `Statistics` must be added to `remap_statistics`, or it loads as zero.
