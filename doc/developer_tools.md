# Developer tools

The screens a developer uses in a running game: the Developer screen, the diagnostics pages, the texture editor and the Data files screen with its export. The general UI rules are in [ui.md](ui.md); the command socket is in [commands.md](commands.md).

- Developer mode (0043) is the Developer mode toggle on the Display tab (`settings.developer_mode`) or `--dev`. It adds a Developer entry to the pause menu, F8 reloads the data, and a Jump double tap toggles flying ([input.md](input.md)).
- Every developer screen is reachable with focus navigation and the pointer, and pauses the simulation like the pause menu under it.
- The editors never write a data file: the texture editor writes its own edits file, the Data files screen writes the data edits overlay ([architecture.md](architecture.md), Data edits overlay).

## Developer screen

`ui_developer.odin`. Rows, top to bottom; the rows between the title and Back scroll when the panel is clamped.

| Row | Entries |
| --- | --- |
| Toggles | Fly mode; no clip (0112: flight passes through blocks); cheat speed (0044, 0087) |
| Overlays | Diagnostics page (steps like F3); statistics overlay (F4); bottleneck overlay |
| Kits | One numbered button per chapter: that chapter's kit |
| Quests | One button per chapter completing the quests before it; Finish active quest (0098: completes it with its rewards and activates the next) |
| Time | Dawn, noon, dusk, midnight |
| Actions | Unlock every recipe and technology; teleport to the landing pad; Screenshot (0053: a PNG under `$XDG_STATE_HOME/mine-oh-belowed/screenshots/`, toasted) |
| Data | The watcher's status and Reload data (0054, like F8 and the reload command; every reload or failure toasts) |
| Editors | Texture editor; Data files |

- The diagnostics and overlay entries act at once. Screenshot and Reload data are frame requests the frame loop serves after the frame, and the editors open their screens. Everything else queues a `Developer_Request` for the simulation, applied when the game resumes, with a toast saying so.
- Cheat speed: three times the movement speed (`CHEAT_SPEED_FACTOR`), hand mining in a tenth of the ticks, a walk steps up one block ledges and a jump reaches about 2.2 blocks. The walk cycle, head bob and footsteps count the walked distance divided by three, and the chop and mining hits keep their period, so nothing looks or sounds faster.

## Diagnostics pages

F3 steps Input, Render, World and off (0086); each draws over a full screen backdrop in the diagnostics font, headed like "Diagnostics 2/3 Render (F3 next)". F4's world statistics overlay is separate, off by default, and shows while the pages are off.

| Page | Shows |
| --- | --- |
| Input | Backend; gamepad buttons and axes with the Steam Controller's physical names; touchpads, gyro (raw, bias, corrected, and whether the view's gyro is Steam's or SDL's), accelerometer, touch sense; mouse and keys ([input.md](input.md)) |
| Render | Build stamp; window mode, monitor, window and render size, window scale, session (x11, xwayland or wayland); vsync, frame cap, fps and frame time over the last second; ticks this frame and the accumulator; fog, weather, day fraction; chunks loaded and drawn with vertices, mesh results and pending jobs, water meshes, torch flames, particles; block, item and UI atlas sizes |
| World | F4's world, streaming, light and player lines (in a field session the feet's latitude, longitude and height above the planet's radius in metres and the sample one spacing under the feet with its material, instead of the block world's position line, 0187); tick, chunk and biome; in a field session whether the feet are in the pod's sealed room and its supply ("sealed room: inside the pod, oxygen unlimited", "... no oxygen" or "sealed room: outside", 0198, `sealed_room_line`); live entities of every kind, loose items, belt lines and their items, the leaf decay queue |

## Texture editor

`ui_texture_editor.odin` (0100), the first of the editors ([DESIGN.md](../DESIGN.md), Editors). Opening it has the frame loop read `data/textures/procedural.sjson` and the edits file again first.

- The panel sits against the left of the safe area without a backdrop, so the world shows to its right: aim at an outcrop right of the crosshair before opening it.
- Left: one row per procedural texture by block name, the selected one with an accent bar; under the list Reset (to the data file's entry), Save and Back.
- Right, above: the selected tile enlarged 6 times beside a field of 6 by 6 tiles, each cell turned, mirrored, slid and brightened as the chunk shader does a top face (`texture_field_source` through `varied_tile_texcoord`), at 3 screen pixels per texel where the column allows (up to 45 percent of its height).
- Right, below: the seed row (Reroll, a new seed from a hash of the tick and the old seed; then the seed, stepped by one with wrapping) and one slider per parameter with the range and step of `ore_texture_parameter_ranges`; they scroll where the column is short.
- Focus: right from a list row enters the controls beside it, left from Reroll returns to the list, down runs through the sliders; on a slider or the seed left and right change the value; right from Reset, Save or Back goes to the slider in their row, up from Reset to the list.
- Every change regenerates the tile on the CPU. While the screen is open the frame loop copies every texture's tile into the block atlas each frame (`update_atlas_block_tile`), so the world shows the change next frame and a data reload's rebuilt atlas takes the edits back.
- Save writes every texture's parameters to `$XDG_STATE_HOME/mine-oh-belowed/texture_edits.sjson` ([content.md](content.md)), a file read when the editor opens and on atlas builds, never watched, logs one `texture: {block = ...}` line per texture and toasts the path. Unsaved edits last until the game exits; a reload keeps the entries changed since the last save. `tools/moc query textures` answers the current parameters.

## Data files screen

`ui_data_browser.odin`, `data_browser.odin` (0129): the fallback editor for every data file without an editor of its own. Opening it has the frame loop read the data directory again first. A panel over a backdrop, as tall as the safe area: the heading ("Data files", or the open file's path), the rows, then a row of buttons.

### The tree

- The data directory recursively, directories first, then files, each sorted by name, dot names skipped; every directory collapsed at first, expansion and selection kept for the run. Rows are indented by depth; a directory shows `>` or `v`, a file its size and an "edited" tag in the accent when the overlay holds a copy.
- Only the visible rows are declared, so the focus walks the tree in order; the rows scroll like the Developer screen's (right stick, wheel, drag, focus kept in view).
- Confirm or a tap on a directory expands or collapses it. On a text file (`.sjson`, `.vs`, `.fs`, `.txt`) it selects the file and opens it in the tree's place; a binary file toasts "Only text files open here".
- An SJSON file opens as a tree of its values (`json.parse`, SJSON, integers kept): objects and arrays expandable with their member count (`{3}`, `[2]`), leaves as `key = value`, an object's keys sorted by name since the parser keeps no order. Any other text file shows one focusable row per line, tabs as four spaces. Only rows inside the scrolled area are drawn, so a long file (the strings, about 1,600 keys) costs little.
- The file is read through the overlay, so it shows what the game loads; the heading carries "edited" when the overlay's copy is shown. A file that cannot be read or parsed shows the error, then the path, over up to four lines.
- Back (B, the touch row's Back, the panel's Back, Pause, a tap off the panel) closes an open file with the focus on its row, then closes the screen. The file closes between frames (the frame request `Close_Data_File`, served by `serve_data_browser`), since the frame's draw list points into its memory.

### Editing

Rule: edits change the tree in the file's memory; Save writes the overlay copy, never the data file (0130).

- Confirm or a tap on a value row selects it and acts: an object or array expands or collapses, a boolean flips, a number or a string opens the keyboard alone in the panel with the value's place (`recipes.3.seconds`) dimmed over the typed text. Done sets the value and returns the focus to the row.
- A number field takes the digits, `-`, `+`, `.`, `e`, `E` (`Text_Field_Characters.Number`). Typed without a point or exponent into an integer it stays an integer; with either it becomes a float; a float stays a float. Text that does not parse, an integer outside 64 bits or a float that is not finite keeps the old value and toasts "Not a number, the value is kept".
- A string takes printable ASCII from a physical keyboard; the game's keys type only letters, digits, space and `-_./`. A string the field cannot hold unchanged (a character past printable ASCII such as `×`, or over 512 characters), a number whose written form has other characters, and a null toast "This value cannot be edited here" instead, so an edit never loses characters.
- Duplicate (a copy of the selected array element right after it, expanded as the original, then selected) and Remove act on a selected array element and are dimmed otherwise. Objects get no new keys, since every loader takes fixed keys.
- An "unsaved" tag shows while the tree's text differs from the text loaded or last saved, so an edit and its undoing leave nothing unsaved. Save (dimmed while nothing is unsaved) writes `<state>/mine-oh-belowed/data_edits/<relative path>` through `<path>.tmp` and a rename, then applies the change as Discard edit does.
- The written file loses the data file's comments and orders every object's keys by name. Save runs between frames (`Save_Data_Edit`), since the reload it starts frees memory the draw list may use.
- Discard edit is dimmed unless the selected file has an overlay copy. It deletes the copy, logs and toasts, applies the change as the watcher would (`apply_data_edit_change`: presentation files such as the strings, the theme and the shaders reload in place, a content file asks for the content reload at once whatever `watch_data` says, `game.sjson` says a restart is needed) and reads the tree and an open file again; unsaved changes go with it.
- Back with unsaved changes drops them and toasts "Unsaved changes dropped".
- When a start up load failed with the overlay on, the overlay is off for the run: a toast at start, and the screen shows in the accent "Data edits are off after a failed load:" with the problem and "Discard the file and restart". The edited tags and Discard edit still work; an open file shows the data file.

### Export

`data_export.odin` (0131). Over the tree, above the buttons: the Export to field (the `export_directory` setting, "not set" while empty) and the Export on save toggle (`export_on_save`), written to the settings file at once.

- Confirm on the field opens the keyboard with "Export to" dimmed over the path; Done trims spaces, expands a leading `~/` and sets the setting.
- Export runs between frames (`Export_Data_Files`). It refuses an empty directory ("Set the export directory first"), a relative one ("The export directory must be an absolute path"), and one that is, contains or lies inside the data or data edits directory ("The export directory must lie outside the data and edits directories", compared cleaned and absolute), since a copy onto its own source would empty it. On Android without All files access it opens that setting's page and toasts "Allow All files access, then export again" ([android.md](android.md), Export and storage access).
- Otherwise it copies the data directory to `<directory>/data/` and the overlay to `<directory>/data_edits/` at their relative paths, each file through `<name>.tmp` with default permissions and a rename, so a failed copy leaves no cut off file and a read only source exports again. Nothing is deleted. It writes `<directory>/export.txt` (build stamp, UTC time, counts), logs, and toasts "Exported to <directory>: N data files, M data edits", or "Export failed:" with the first problem and its path, where it stops.
- With Export on save and a directory set, every Save and Discard edit also writes or deletes that file's copy under `<directory>/data_edits/`. A failure is logged every time and toasted once ("Could not export the edit:") until a sync or an export succeeds; without All files access the settings page opens with that first toast only.
- The export copies every file (about 475) in one frame on the main thread, so the game stands still meanwhile, a second or more on the phone's shared storage. Nothing is read back from the directory.
