# 0174: Foundation frames and placement on them

Status: todo (after 0173; the switch of the simulation's grid to frame cells)

## Goal

The local grid: a foundation defines a frame (origin, up along the radial at placement, any yaw, the pitch from data), its cells carry an occupant index, a foundation placed by snapping joins the frame exactly and one placed free starts an island, frames never merge; the simulation's block coordinate becomes a frame cell, so the existing placement rules, belts and footprints run on frames (0167, Frames and foundations; decisions 10, 12, 22).

## Change

- A `world_frame` file: the frame record (id, origin in the planet's fixed point, orientation as a rotation in fixed point, pitch), the cell to world and world to cell transforms, the per frame occupant index (handle plus flags: solid, blocks light, blocks water), and the frame table of the world.
- The simulation's `World_Coordinate` for entities becomes a frame cell (frame id and integer triple); `Block_Query` and `Block_Write` of the entity tick context (0155) answer from the frame's occupant index for cells and from the field for terrain, and the placement rules, the belt lines, the splitters and the footprints keep their integer logic unchanged. Say in the notes every place the coordinate type change reached.
- Placement: the ghost snaps to the targeted frame's cells and rotations; a foundation placed with no frame under the reticle starts a new frame with up along the radial at the hit point and the yaw of the player's facing, rounded to the nearest 15 degrees; a foundation placed by snapping extends the frame.
- A frame never re-tangents; the terrain under a frame is not changed by placing it.
- Sealed rooms, walls and air wait for M15.
- `doc/architecture.md` (frames beside the world storage), `doc/logistics.md` (belt placement on frames), `doc/code_map.md` updated; the cell occupant index item 0164 is closed into this one with a note.

## Verify

- The build and check commands of 0168; the existing belt, splitter, inserter, drill and placement tests run on a single frame where they ran on the block grid.
- Tests: a free foundation starts a frame whose up is the radial at the hit point; a snapped foundation joins and the frame's cell count grows by one; two free foundations fifty metres apart are two frames; a machine placed on a frame occupies its footprint's cells and a second machine over them is refused; an entity's world position is the frame transform of its cell; a save round trips frames and occupants.
