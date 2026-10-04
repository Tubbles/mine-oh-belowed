# 0215: The placement editor and the tools radial

Status: todo (2026-10-04, the user's design after the 10 by 10 by 12 furnace landed (0212): "we need to have placement of such large machines more advanced ... start with only a ghost outline of the footprint ... center on the aimed cell, and as it is placed, the full ghost is shown, and we enter a special control state"; folds 0213)

## Goal

A 5 m machine at a 2 m reach cannot be seen whole while it is placed, and today Place puts it at the hit in one press with its corner cell on the aimed point. The player gets a placement editor: a flat footprint outline centred on the aimed cell, anchored in the world with one press, then a full ghost the player walks round and nudges, rotates, commits or cancels. The editor is a mode the player turns on and off in a new tools radial on the Pipette's button, which also becomes the home of seldom used tools and modes.

## Change

- **The tools radial.** The Pipette's bindings (gamepad D-pad Up and R5, keyboard Q, the mouse's middle button, the touch overlay's pipette control) open a radial menu (the hotbar radial's widget) while held: the entries are Pipette and Placement editor (shown with its on or off state), with room for later tools and modes; the look input steers the highlight (the right stick, the mouse, the finger), release selects, the dead centre cancels. A tap with no steering is Pipette as before, so the pipette stays one press.
- **The editor state.** Per local player, session state, off at a session's start, not saved. On: Place with a machine held whose footprint exceeds 2 by 2 by 3 cells (width, depth and height each at most 2, 2, 3 to be placed directly; belts, poles, pipes, chests and the small machines) starts the editor flow below. Off: a large machine is placed in one press as today, but centred on the aimed cell (the rule of 0213, folded here: an odd footprint's middle cell on the hit, an even one's centre corner; a 1 by 1 footprint unchanged). A foundation block over the threshold (5 by 5, 10 by 10) goes through the editor too when it is on.
- **The outline.** With the editor on and a large machine held, the ghost is a flat outline of the footprint on the ground (no height), centred on the aimed cell, with an arrow for the front, white, red where the placement would be refused (too steep, a cell taken, no foundation under a bottom cell) by the checks the ghost uses today (`field_placement_refusal`, `bare_ground_placement_refusal`, `frame_placement_refusal`).
- **The anchor.** Place on a white outline anchors it: the ghost becomes the machine's model, see through, standing at that spot, and the editor mode starts. Place on a red outline is refused with the reason toasted, and no mode starts.
- **The mode.** The ghost stays anchored in the world while the player walks round it with the full movement set. Each nudge moves the origin one cell along the frame's axes (on bare ground the frame re-stands on the ground under the moved centre, so the ghost follows the terrain), each rotation turns the footprint 90 degrees about its centre, and every change re-runs the refusal check and re-tints the ghost. Commit on a white ghost places the machine through the ordinary placement command carrying the origin cell and the rotation (no hit), so the simulation and the lockstep see one command as today; commit on a red ghost is refused with a toast. Cancel drops the ghost. Changing the held hotbar slot or losing the held item cancels too. The mode's state is presentation only; nothing is saved or hashed.
- **The ghost.** The full ghost draws the machine's model see through (the footprint box stays the fallback for a machine without a model), with the refused tint of the block ghost.
- **The docs.** `doc/input.md` (Bindings: the radial, the editor's table), `doc/ui.md` (the tools radial beside the hotbar radial), `doc/touch_overlay.md` (the editor's layout), `doc/architecture.md` (Placement on frames: the command carries an origin and a rotation), `doc/presentation.md` (the outline and the model ghost), `doc/content.md` (the threshold key).

## Controls

The control design (main agent, 2026-10-04), in modes:

- **World, the tools radial held.** Hold the Pipette control (D-pad Up or R5, Q, the middle mouse button, the touch pipette): the radial shows; steer with the look input; release on an entry selects it; release in the dead centre or a tap selects Pipette. Nothing else changes while it is held.
- **World, the editor on, a large machine held.** Every control keeps its meaning; only the ghost differs (the flat outline centred on the aimed cell, with the front arrow), and Place anchors instead of placing.
- **The editor mode** (after the anchor), gamepad first:

| Control | In the editor |
| --- | --- |
| Left stick, right stick, gyro, trackpads | Move, Look, as in the world (walk round the ghost) |
| A | Jump |
| B | Sneak |
| Left stick click | Sprint |
| D-pad Up, Down | Nudge the ghost one cell away from and towards the player, along the frame axis nearest the player's facing |
| D-pad Left, Right | Nudge the ghost one cell across |
| Y (Rotate_Building), L5 | Rotate the ghost 90 degrees about its centre |
| L2 (Place) | Commit |
| R2 (Mine) | Cancel: the world's build and remove pair becomes the editor's yes and no |
| L1, R1 | Hotbar previous and next, which cancels the editor (the held machine changes) |
| X (Open_Inventory) | Opens the inventory as in the world; the ghost stays anchored and the editor resumes when the screen closes |
| Menu (Pause) | The pause menu, with a `Cancel placement` row while the editor runs (the touch fallback, as Skip arrival is) |
| View (Open_Map) | The map, as in the world |
| Keyboard and mouse | Arrows nudge, R rotates, right click commits, left click cancels, Escape opens the pause menu with its row |
| Touch | The virtual gamepad's bindings above; the overlay shows a placement layout with the four nudge buttons, rotate, commit and cancel (`serve_touch_layouts`) |

What stays unavailable in the mode: the Pipette and its radial, Drop_Stack and Interact (A is Jump alone, as a held machine never interacts). A world control never gains a second meaning while an item is held outside the mode: the editor is a mode the player entered on purpose, which is what the keybinding rule allows.

The cancel choice (user, 2026-10-04: "we need to keep sneak, so during placement editing we need to find some other way to cancel"): R2, since Place and Mine are the world's build and remove pair and Mine has no meaning while placing; the hotbar change and the pause menu row are the other two ways out.

## Verify

- Tests: the outline's centre for odd and even footprints and for 1 by 1; the threshold (2 by 2 by 3 places directly, 2 by 2 by 4 and 3 by 1 by 1 enter the editor when it is on, every size places directly with it off, centred); a red outline refuses the anchor with the reason; nudge and rotate about the centre on a frame and on bare ground (the re-stood frame follows the terrain); the refusal re-check after a nudge; commit sends the placement command with the origin and the rotation and the placed machine matches the ghost; cancel, the hotbar change and the pause row drop the ghost; the radial selects Pipette on a tap and the editor on a steered release; the editor state is not in the save or the hash; the touch layout's buttons map to the actions; the UI audit shows the editor's HUD line and the radial.
- The couch: the furnace placed where the player aims, walked round and nudged into place; a chest still placed in one press.
