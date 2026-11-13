# User interface

How every screen is built, so "couch first" and "one coherent game" hold on every panel. The design intent is in [DESIGN.md](../DESIGN.md), User interface; input in [input.md](input.md); the touch overlay in [touch_overlay.md](touch_overlay.md); the HUD in [hud.md](hud.md); the developer screens in [developer_tools.md](developer_tools.md).

- An immediate mode UI in Odin over raylib draw calls (no raygui: mouse centric, no focus navigation), laid out in UI units where 1080 span the screen height.
- One focus model for every device: the d-pad and sticks move a focus cursor; the pointer (mouse, right trackpad, finger) focuses what it hovers and activates by a tap.
- 10 foot rules: large text, a safe area, no hover only information, every string from `data/strings/en.sjson`.
- Any pointer drags stacks between slots, and a tap or click off a panel closes it; on touch the glyph bar becomes a row of buttons.

## Principles

- Text: body 24 units (`UI_BODY_TEXT_SIZE`), headings 32, the glyph bar 28, scaled by the screen height, the UI scale and the text size. The safe area keeps a 5 percent margin (`UI_SAFE_AREA_FRACTION`).
- No hover only information: tooltips are panels Y opens, docked to the current panel. Item slots show their tooltip by themselves once the focus rested `UI_TOOLTIP_DELAY` (0.4 s) on a stack (0094); no setting turns it off.
- Radial menus (the hotbar, the letter wheel) show while the pad is touched; the highlight follows the finger's angle, release selects, the dead centre cancels. The tools radial (0215, [input.md](input.md), The placement editor) shows while Pipette's control is held: the look input steers, release on an entry selects, a tap released before it shows is Pipette and the shown radial's dead centre selects nothing.
- Every player facing string comes from the string table by key; numbers go through one formatting procedure per unit (per minute, kW, MW, L, blocks).
- Held directions repeat after 350 ms, then every 80 ms (`UI_REPEAT_INITIAL_SECONDS`, `UI_REPEAT_STEP_SECONDS`).

## Architecture

- `ui_begin` resets the frame; screens declare widgets, each call returning its result; `ui_end` resolves focus and hover (`ui_resolve`, pure) and runs a deferred draw list (`ui_draw.odin`, the only part calling raylib), so focus resolved this frame draws this frame.
- Activation is decided inside the widget call (Confirm on last frame's focus, or a tap released this frame); only focus moves reach widget results a frame late.
- The UI runs after the simulation, so a screen opening or closing reaches the world a frame later.
- Screens never write the simulation: research, crafts and their cancel, a recipe choice, the power switch, assembly and launch, catalogue orders, splitter and filter settings, a foundation block's size and height (0193), the toolbar edit mode's moves, clears and carousel (0279), the hotbar radial and the Developer screen's toggles queue a `Player_Command` (`Screen_Context.player_commands`) that the next tick applies, so the result shows a frame later ([architecture.md](architecture.md), Simulation). Before queuing, the screen runs the pure refusal check the tick repeats (`assembly_refusal`, `recipe_change_refusal`), so a refused action toasts at once and never queues. A command already taken by the lockstep driver and not applied still counts as pending (`Screen_Context.unconfirmed_commands`), so a toggle shows its new state at once and a second press undoes it. A closed machine panel queues `Close_Machine_Command` once. The slot transfers queue too (0179): A (with L1, the split) and X on a slot, the end of a drag or of Even Distribution, quick moves, Take all, Store all, Fill, the touch row's transfers, Drop and the inserter's hand. Nothing is predicted: the slot and the hand show the change one frame later offline and the latency window later online, and a press on a frame older than a transfer still on its way can be refused by the tick (a toast). A pointer drag whose pick up has not reached the tick yet keeps dragging, and its drop lands after the pick up.
- While no tick can run for a while (a world waiting for its chunks, a join catching up) the frame draws a loading notice over the screens (`loading_notice`, `draw_loading_notice`).
- `Ui_State` holds the focus and focus panel, scroll offsets and selections keyed by widget id, the screen stack, radial state, repeat timers, the pointer, and the device that moved last (whose glyphs the glyph bar shows). Layout helpers compute rows, columns and grids; no constraint solver.
- Every screen reads one `Screen_Context` (`ui_screens.odin`, built per frame by `make_screen_context`) grouped by owner: the process fields, the content as the session sees it (an embedded `Simulation_Content` with the session's technologies, found schematics and generator, plus the presentation tables), the simulation fields, the session views (`views`), the developer tools (`Developer_Context`) and the touch layouts; `draw_hud` takes a `Hud_Context` beside it (`hud.odin`: the touch derivations and the biome the frame samples once under the player).

### Render pixels

Rule: the UI lays out in render pixels, the framebuffer's `GetRenderWidth` by `GetRenderHeight` (0085), so text rasterises at the panel's size on a scaled Wayland desktop.

- The 2D passes (UI, diagnostics, underwater overlay) reset raylib's modelview to the identity first (`begin_render_pixel_drawing`), since raylib multiplies its DPI scale in. UI clips go through rlgl, not `BeginScissorMode`, which scales its box.
- raylib's mouse scale is reset to 1 every frame and GLFW's cursor is scaled per axis by framebuffer over window size (`pointer_to_render_pixels`). The look delta stays in window coordinates; the trackpad pointer moves in UI units. On X11 at scale 1 all of this is the identity.

### Screens

Screens stack over the world and the HUD (`UI_SCREEN_STACK_CAPACITY` 8). Any open screen blocks the world's actions; a pausing screen anywhere in the stack also pauses the simulation (`screen_pauses_simulation`), in split screen only the first viewport's (0178).

| Pause the simulation | Keep it running |
| --- | --- |
| Pause, Settings, Developer, Textures, Data files, Touch layout, Title, New world, Load, Delete confirmation, Multiplayer, Tech demos, Tech demo | Inventory (the crafting view), Configure pop-up, Toolbar edit, Machine, Recipes (the picker and the station browser), Journal, Power, Statistics, Technologies, Map |

- The stack (`handle_screen_keys`, 0385), the world being the empty stack. Push: the world's keys open their screen (the inventory binding and C both the crafting view, on its inventory and on its schematics half, 0277), a panel its pop-ups (an assembler's recipe picker, a crafting station's browser, a lab's Research), the crafting view its configure pop-up and the toolbar edit mode, the pause menu Settings and Developer; the pause menu's Journal, Power and Statistics rows replace the menu, so their window lies on the world. Replace: LT and RT (Q and E) on a window of the carousel (Window carousel). Pop one level: Back (B, Backspace), Pause over a screen, a tap off the panel and a window's own key (C, J, P, N, T, M, View, C popping the crafting view and the recipe browser), the first press closing an open info panel alone; Open_Inventory pops the crafting view, the recipe browser, Research and a machine panel, except when the same press is the context action (the gamepad's X sorts) or a window's step (the keyboard's E steps on a window and closes a panel). So a window opened from the world closes to it, Research opened from a lab's panel returns to the panel, also after a step, the configure pop-up and the toolbar edit mode return to the crafting view, the picker to its panel and Settings to Pause. The pause menu's Resume clears the stack.
- A screen opened from the world focuses the widget it prefers (`ui_prefer_focus`), else its first (0094); the inventory and machine panels prefer the first stack of the selected toolbar slot's kind (`selected_kind_slot_id`, 0278). The focus is forgotten on the first frame without a screen (`run_screens`); a screen pushed over another keeps it.
- The pause menu: Resume, Cancel placement (while the viewport's placement editor is anchored, 0215: it cancels the editor and closes the menu; a split screen guest's menu shows its own editor's row), Skip arrival (during a new world's fall, 0200), Journal, Power, Statistics, Save, Settings, Developer (developer mode), Quit to title, Quit. Skip arrival shows until the hit (`field_arrival_skippable`, `Screen_Context.arrival_skippable`), queues `Skip_Arrival_Command` and closes the menu; it ends the fall for every player. During the fall Pause is the only binding that opens a screen from the world and the pause menu has no Journal, Power or Statistics row (`Screen_Context.arrival_falling`, `handle_screen_keys`, `pause_screen_buttons`). A split screen guest's (any viewport but the first, 0178) has Leave split screen in place of the two quits, and its world runs on while it is open; one whose player's join tick has not run yet shows only Resume, Settings and Leave split screen, and no other screen opens there (`WAITING_PLAYER_SCREENS`).
- Sounds go to `Ui_State.sound_events` for the frame loop: a move click when the focus moves between widgets (not the fallback on opening), a confirm click on an activation, a back click on Back over any screen but the title.

## Focus and navigation

Every interactive widget has a rectangle and a stable id. `find_focus_neighbour` (0093) moves the focus in two passes:

1. The nearest widget ahead in the focused widget's row or column (same panel, extents overlapping across the direction), ties to the smallest sideways offset.
2. Only when that finds nothing, the nearest in the direction with the sideways offset weighted double (`UI_FOCUS_PERPENDICULAR_PENALTY`), wrapping inside the panel.

- A confirms, and R1 or L1 held with it make it five or the most where a screen gives them a meaning (Item slots, Recipe browser, 0276). B backs, a flick of the right stick (`[` and `]`) steps the window's tabs, the triggers (Q and E) step the windows, Y opens the info panel, X is the context action (sort, configure, clear the crafting queue on the crafting view's schematics, cancel the last craft in the station browser, clear a shortcut in the toolbar edit mode). The bumpers alone do nothing. Tabs are not focus targets (the crafting view's included), except the recipe browser's category row.
- `Adjusts_Horizontally` (sliders, steppers, choices) makes left and right change the value; `Adjusts_Vertically` does the same for up and down.

## Pointer

Rule: the mouse, the right trackpad's pointer and a finger activate a widget by a tap (0132): the widget under the press (`Pointer_Press`) activates when the pointer lifts over it without having left `UI_SLOT_DRAG_SLOP` (16 UI units) of the press (`pointer_tapped`). Anything else activates nothing; Confirm sounds on the release.

- The pointer focuses what it hovers. The mouse sets it, the trackpad moves it (pointer speed setting), a stick or d-pad step hides it. The right pad click is a click while the pointer shows and Confirm while it is hidden.
- Acting on the press instead: the tab strips and a window's title row arrows; the touch layout editor's elements (select and grab); item slots (drag, below); Left Control or Left Shift with a click on a slot (quick move, split).
- A stepper (`ui_stepper`) steps by the half tapped.
- A slider decides a press on its track by the first movement past the slop (`slider_pointer_value`): along the track is its drag (the value follows the pointer on frames it moved), across is its list's scroll, a release within the slop sets the value at the press. The UI scale and text size sliders (`ui_layout_slider`) apply a drag only on release, so the track stays under the finger.
- A press in a scroll region or list (`scroll_region_end`, `ui_list`, `scroll_list_end`) that leaves the slop scrolls it (`pointer_drag_scroll`, the first slop included) and cancels the tap; not on an item slot, a slider's track drag or an editor element. The focus stays where the drag put it, even out of view (`focus_scrolled_away`), until it moves, a step is taken or a screen asks for a focus.
- A widget registered in a scroll region or list takes the pointer only inside its clip (`Ui_Widget.clip`, `point_in_clip`, 0277): the part scrolled out is not hovered, pressed or focused by the pointer, so a row under the header above a list leaves the header its clicks. Focus navigation still reaches it, and the region scrolls it into view.
- The stored pointer is in UI units and follows a UI scale change (`rescale_pointer`).
- A toggle's knob slides from where it was drawn last frame (`Knob_Position`); one not drawn last frame starts at its value, so a value changed while its screen was closed does not slide in as if flipped.

### Tap or click off a panel

A tap or click off the screen's content with nothing held (any pointer: the press runs through `advance_slot_drag`) closes the top screen as Back (0137, `screen_closes_on_outside_tap`). Off the content is outside its panels (the glyph bar's aside), its widgets, and the bottom strip of glyph bar and hotbar (`pointer_outside_screen`). Every screen with a panel closes this way (the pause menu resumes, the delete confirmation says No, the Data files screen closes an open file first); the title and the touch layout editor do not. Not while a keyboard is open: with the system keyboard the tap ends the entry and the next one closes.

## Item slots

One slot code serves the inventory, the machine panels and chests (`ui_item_slot`, `inventory_interaction.odin`, `quick_transfer.odin`).

### Gamepad

- A picks up the focused stack and drops, merges or swaps on another slot. L1 held with A (Left Shift with Enter) splits it (the larger half, so one item lifts whole). X sorts the active grid; in the inventory on a configurable item it opens the configure pop-up instead (Screens, Configure pop-up).
- R1 held with A (Left Control with Enter or a click) quick moves (0078) across a machine panel by the inserters' rules (fuel to the fuel slot, ore to the input). A second press within half a second, or a hold, moves every stack of the item. What does not fit stays. The inventory is one grid (0278), so there it does nothing.
- The bumpers change A only with an empty hand (`slot_act`, 0276): with a stack in hand A places, merges or swaps whatever is held, and both bumpers held leave A alone. A modified press takes the slot's activation, so neither the quick move nor the split also picks up.
- Holding A with a stack in hand while the focus crosses machine slots spreads it evenly over them on release (Even Distribution).
- A held stack follows the focus and the pointer, and returns to its slot when the screen closes. Machine inputs take only what the machine uses; a rejected drop stays in hand.
- A broken machine's panel (0201, [content.md](content.md), Machines on bare ground) says "Broken down, tear it down" in the danger colour under its description.
- Machine panels have Take all, Store all and Fill. An inserter's "In hand" slot shows what its arm carries: A or a drag lifts it, R1 with A moves it to the inventory, it takes nothing in (0079).
- In the inventory the right stick click (keyboard X, `Menu_Drop`) drops the held stack, else the focused one, on the ground (0062); the glyph bar shows Drop then. Pick up rules: [logistics.md](logistics.md), Loose items.
- In the world `Drop_Stack` (d-pad down, keyboard X, the touch overlay's long press on the selected hotbar slot) drops the first stack of the selected toolbar slot's kind in front of the player as a loose item ([hud.md](hud.md), Toolbars).

### Pointer

Rule: the pointer moves stacks by drag and drop (0124, `Slot_Drag`); a click on a slot activates nothing.

- A press that leaves the slop picks the stack up; the release drops, merges or swaps on the slot under it (`apply_slot_primary`, filters apply). What is still held returns to the drag's origin (`return_held_stack`): a drop on another item swaps, a drop off the slots returns; a leftover that fits nowhere stays on the cursor.
- A drag drops onto a filter or hand slot; one out of it lifts nothing and ends, as does one whose slot a machine emptied.
- A tap focuses the slot. Resting `TOUCH_HOLD_SECONDS` (0.25 s) on a stack of two or more splits it and drags the half.
- With a stack held, a press drags it at once. Confirm sounds on pick up and drop.
- Pick up and the rest's split reach the screens as a plain Confirm and `pointer_split` (`Ui_State`) on the slot, so every slot screen applies them as the gamepad's. Even Distribution stays the gamepad's.
- Ctrl or Shift held with a click quick moves (on a machine panel) or splits the pressed slot on the press, focusing it and starting no drag (0276). With a stack held a modified click drags as a plain one and sounds only on the drop, and a drag's pick up is never a quick move. Off the item slots a modified click is a plain one: it focuses, drags or taps off the panel as a click without the modifier.
- With the `Touch` pointer source the dragged stack draws a slot height above the finger.

### Active grid

The grid of the slot that last held the focus (`Active_Slot`: the inventory's 45 slots or the machine's), kept while the focus is on a button, forgotten when the screens close.

- Sort sorts it alone, the inventory whole (0278): the toolbars name kinds, so no slot keeps its place.
- Split takes the larger half of the active slot's stack onto the cursor, as L1 with A.
- Transfer all moves the active grid's stacks, Transfer same those of the active slot's item, to the paired grid (`transfer_target_grid`) in a machine panel: into the machine as the quick move stores, and from the machine into the inventory. What does not fit stays. The inventory alone has no paired grid.

## Touch

Rule: on Android and while the touch overlay is on (`Ui_Input.pointer_is_touch`) the pointer is the first touch (source `Touch`), screens show the touch row instead of the glyph bar, and a tap on a recipe or technology selects without committing (`tap_selects_only`; Confirm still commits). The keyboard and gamepad keep the glyph bar.

### Touch button row

`ui_touch_row` (0125, 0137) draws buttons without glyphs in the glyph bar's place, in `Touch_Button`'s order, Back last on the right. Back (and the toolbar edit mode's Done) sets the frame's Back, closing the screen as B does with B's sound (`Ui_State.back_tapped`).

| Screen | Row |
| --- | --- |
| Crafting view, inventory half | Sort (Configure in its place while the active slot holds a configurable item, the row laid out for Configure), Split, Drop (the active slot's stack), Assign (0278; a long press opens the toolbar edit mode, 0279), Back |
| Crafting view, schematics half | Assign (0278, its long press as on the inventory half), Craft, Craft 5, Craft max, Cancel last, Clear queue (0277), Back |
| Toolbar edit | Clear (X's press), Done (0279) |
| Machine panels | Clear (an inserter's or splitter's filter), Sort, Split, Transfer all, Transfer same, Back; laid out for Clear, so the others keep their places |
| Recipe browser | Craft, Craft 5, Craft max (0276), Cancel last (Choose when picking), Back |
| Technology screen | Research, Back |
| Map | Zoom in, Zoom out, Back |
| Pause, settings, developer, texture editor, Data files, journal, power, statistics, new world, load, delete confirmation | Back (`ui_glyph_bar_or_back_row`) |
| Title, touch layout editor, an open keyboard | None |

- Craft, Craft 5, Craft max, Choose and Research act only while the list or the grid shows the selected entry; the row draws before the list's focus settles, so focusing its button keeps the selection.
- The row sits right of the hotbar (which draws under screens) when that strip holds every label (`touch_row_strip`, `touch_row_natural_width`), else across the safe area over the hotbar, which takes no input under a screen (the slot screens at UI scale 1 on the Deck's 1280 by 800 and at 1920 by 1080; a 2400 by 1080 phone holds them beside it). Buttons still too wide narrow, the widest first, with an ellipsis (`fit_button_widths`); the audit checks that no touch case cuts a label.
- The HUD's world hints draw nothing on touch.

## Widgets

Label, button, toggle (a switch whose knob slides over an eighth of a second), slider, stepper, choice, tabs, list, slot grid, item slot, progress bar, tooltip, radial menu, text field, glyph bar, touch row, toast.

- Single line labels ellipsise; descriptions and tooltips wrap. Toasts show top left for 4 s, at most 4, wrapped to three lines within 0.55 of the safe width.
- The glyph bar sits bottom right and drops hints from the end, keeping Back: the menus' bar is one row over the safe width (`ui_glyph_bar`). The HUD's has its own layout beside or above the hotbar ([hud.md](hud.md), Layout); both draw through `ui_glyph_rows`. It shows the bound control (0151, `glyph`), the first binding when an action has several ([input.md](input.md), Bindings): the pad button's icon on a gamepad, a key cap with the key's name on the keyboard and for a pad control without an icon (a paddle). The names that read poorly have labels in the string table (`control_label_keys`), others read as written (`PAGE_DOWN` as Page Down, `LEFT_PADDLE1` as Left Paddle 1).
- Tooltips dock beside the panel, else below or above the focused widget, inside the safe area. A panel without art inside another (the crafting view's halves) docks them beside the panel around it (`tooltip_dock_rectangle`, 0277).
- Panels sit in the safe area above the glyph bar; a taller panel is clamped and its rows scroll with the focus kept in view (the pause menu, new world, developer, a machine panel's machine side, which wraps its slot rows).

`test_every_screen_stays_inside_the_screen` (0046) runs every screen headless and requires every draw command inside the screen and its panel:

| Case | Sizes and scales |
| --- | --- |
| Matrix | 1920 by 1080 and 1280 by 800 at UI scale 1.0, 1.2, 1.5; 2880 by 1920 at 1.0 |
| Split screen | A quarter of 1080p (960 by 540) and the stacked half (1920 by 540) at 1.0; the side by side half (960 by 1080) at 0.5, the scale `viewport_ui_scale` gives it (0178). The UI follows the height, so 960 by 540 at 1.0 and 960 by 1080 at 0.5 lay out in the same units as 1920 by 1080 at 1.0: they check the pixel rounding, not a smaller layout. 1920 by 540 is the one new shape (32:9). Whether text at half the pixel size reads from the couch is the couch's to judge |
| Text | Each size at text size 1.6 too, widths measured scaled, heights at the layout's size (0074) |
| Deck | 1280 by 800 at UI scale and text size 1.1 (0076) |
| Devices | Keyboard and gamepad glyphs, the touch row; also the longer panels with descriptions and a Notes tab with every note unlocked |
| Viewports | A split screen guest's pause menu, also while its player joins, the HUD under a lost pad's notice (0178) |

## Settings

Tabs: Display, Audio, Controls, Accessibility, Bindings (the effective bindings, read only). Rows apply at once. Changed settings go to `config.d/90-settings.sjson` whenever no settings screen is open (`write_changed_settings`), so the screen's changes land when it closes and other changes at once.

| Tab | Row (`settings.` key) | Values, default |
| --- | --- | --- |
| Display | Window mode (`window_mode`) | Windowed, Borderless (default), Fullscreen |
| | Resolution (`resolution`) | Native `[0, 0]`, then 1280 by 720 to 3840 by 2160 up to the monitor's size |
| | Vsync (`vsync`); Frame rate cap (`frame_rate_cap`) | On; Off, 30, 40, 60, 90, 120, 144, 165, 240 |
| | Field of view (`field_of_view`) | 60 to 110 degrees vertical, 70 |
| | Sprint view widening (`sprint_field_of_view_kick`) | 0 to 15 degrees, 6; eased over `SPRINT_KICK_SECONDS` (0.3) while sprinting and moving |
| | Third person distance, shoulder (`third_person_distance`, `third_person_shoulder`) | 2 to 8 blocks by 0.5, 4; -1 to 1 blocks right by 0.1, 0.6 (follows the yaw; a wall pulls the camera in) |
| | Weather (`weather`) | On; off: clear, no rain, snow, sway or cloud shadows (0063) |
| | Sun shadows (`sun_shadows`) | Default: the build's data row (on for the desktop builds and the Steam Deck, off on Android, 0328); the toggle shows the effective value and writes on or off |
| | View distance (`view_distance_metres`) | 256 to 1024 metres by 256, 1024 (0343): how far the field is drawn ([presentation.md](presentation.md), Field meshes); a value between the steps in a file is kept |
| | Head bob (`head_bob`) | On; 0.03 blocks per step, 0.05 sprinting (0066) |
| | UI scale (`ui_scale`); Pointer speed (`pointer_speed`) | 0.75 to 1.5 by 0.05, 1; 0.5 to 3, 1.5 |
| | Bottleneck overlay; Autosave (`autosave_minutes`) | Also O; Off to 60 minutes, 5 |
| | Developer mode; Font, Diagnostics font (`font`, `monospace_font`) | [developer_tools.md](developer_tools.md); Text, below |
| | Two player split (`split_screen`) | `stacked` (default, each player keeps the full width and so the field of view) or side by side (`Split_Screen_Layout`); three and four players take quarters (0178) |
| Audio | Master, Effects, Ambience volume (`master_volume`, `effects_volume`, `ambience_volume`) | 0 to 1, shown as percent in steps of 5; 0.8, 1, 0.7 (0068) |
| Controls | Gyro, stick, gyro and trackpad sensitivity, invert pitch | Sensitivities 0.25 to 3, 1 |
| Accessibility | Text size (`text_scale`) | 0.8 to 1.6 by 0.1, 1 |
| | Marker colours (`palette`); Reduced motion | `default`, `colour_blind`; off |
| | Sneak, Sprint (`sneak_hold`, `sprint_hold`) | Hold, Toggle ([input.md](input.md)) |
| | Touch controls, Touch aiming (`touch_overlay`, `touch_interaction`) | `auto`; `tap` or `crosshair` ([touch_overlay.md](touch_overlay.md)) |
| | Text entry keyboard (`on_screen_keyboard`) | `system` or `game`, `system` |
| | Touch layout, Edit touch layout | Saved in the user's `touch_overlay.sjson`, not the settings |

- Effects volume covers footsteps, digging, placing, menu clicks, the launch, the landing and the discovery chime; Ambience the biome ambience, the rain and the machine hum.
- Text size multiplies every text size on top of the UI scale (`ui_text_width_in_weight` measures scaled); the layout keeps its sizes, so large text ellipsises sooner (0074).
- Colour blind markers are blue, orange, black and white, then the rest of the Okabe and Ito set, apart under deuteranopia and protanopia and by lightness, for the bottleneck markers and the map; under them every map machine dot takes the palette's machine colour.
- Reduced motion turns off the head bob, the sprint widening and the weather's motion (the sky still greys, the rain is still heard), holds the flames' flicker, the furnace embers' pulse and the light's flicker and lets the flames rise at their slow layer only, holds the focus outline at its thickest and shows Mission Control's lines whole. The rows it overrides keep their values.
- Resolution is the window's size in Windowed and the video mode in Fullscreen; Borderless covers the monitor, so the row is dimmed and shows the monitor's size, read once at start (0080). raylib lists no video modes, hence the fixed list; a configured value outside the lists is kept and shown as numbers.
- Under XWayland (GLFW took X11 while `WAYLAND_DISPLAY` is set) on a scaled desktop Borderless shows the scaled size, for example "1694 x 1129 (desktop scaled)", and the tooltip names the ways to full size ([build.md](build.md)).
- In Steam Game Mode gamescope presents the window full screen whatever the mode, and a windowed resolution is the size gamescope scales up. `display.odin` holds the mode transition table.
- `settings.shadows` from an older build is ignored with one log line (`RETIRED_CONFIGURATION_KEYS`).

### Steam Deck preset

On a start with `SteamDeck=1` and `settings.deck_preset_applied` false, `deck_preset.odin` (0076) sets a frame rate cap of 40, weather on, UI scale 1.1, text size 1.1 and Borderless, and writes the settings file with `deck_preset_applied = true` before the window opens (log: `settings: Steam Deck preset applied (...)`). A settings file written before the marker gets the preset once. The marker is an ordinary key: true in a `config.d` file keeps the preset off, false applies it again. A `--set` naming one of the preset's keys holds it off for that start. The Deck keeps the usual five percent safe area, checked by eye on the device.

## Screens

### Window carousel

The windows the world opens are one carousel (0385, after Techtonica, [inspiration.md](inspiration.md)), `ui_window_carousel.odin`: Inventory (the crafting view, which took the Recipes window's place too in 0277), Journal, Research, Map, Statistics, Power, and round.

- Opening: each window's key opens that window (the inventory binding the crafting view on its inventory half, C on its schematics half, J, T, M and View, N, P), and the pause menu's rows the journal, the power overview and the statistics; the gamepad reaches the others with the triggers.
- The step: LT and RT (Q and E, `Window_Previous` and `Window_Next`, 0276) put the previous or the next window in the top screen's place (`step_window_carousel`, `replace_top_screen`, in `handle_screen_keys` ahead of the closes), so the depth and what lies under the window stay: Back from any window returns to the world, or to the lab's panel that opened Research. On the keyboard E steps too, though it is also Open_Inventory: on a window the step wins, and Esc or Backspace close. No sound.
- The new window takes its preferred or first focus; an open info panel stays open. A window keeps what it kept before: the browsers' filters, categories and focused rows and the crafting view's tab and Unlocked only (`Session_Views`), the crafting view's half (`Ui_State.crafting_half`), the journal's and the statistics' tab (`Ui_State.selections`); the map centres on the player at every opening.
- The title row (`ui_window_title_row`) heads every window: the window's title, fitted and centred, between a left and a right arrow that step on a press (the pointer and touch). Off touch LT and RT (Q and E) stand outside the arrows, so no glyph bar names the window step. It is no focus target.
- Outside the carousel, where the triggers do nothing: the machine panels, the recipe picker and the station browser (`window_in_carousel`), the configure pop-up, the toolbar edit mode and the menus.

### Crafting view

The inventory binding's window (0277, after Techtonica, `ui_crafting_view.odin` and `inventory_screen`): one panel titled "Inventory", the inventory half on the left, the schematics half on the right. The machine and chest panels keep their transfer view.

- Layout (`crafting_view_layout`): the panel takes the safe area's height and at most `CRAFTING_VIEW_WIDTH` (1712). Under the title row lie the inventory half (784, the slot grids), the seam (32, a line of the border's width at its centre) and the schematics half, the rest (W). That half holds the category tabs, a header with "Unlocked only" and the queue summary (the accent while the queue waits), and the body: with W of 500 or more a grid of at most five columns left of the recipe detail, which keeps at least 300, and under 500 (stacked) a two row grid above the detail, whose tail is cut where it ends. Stacked, the toggle and the summary each take a row of the half's width, and the toggle reads "Unlocked" where "Unlocked only" does not fit beside its knob. At 1080p W is 864: five columns and a detail 400 wide. At 1280x800 and UI scale 1.5, the smallest, W is 188.8: tabs of 31.4, the toggle's label 92.8 wide, the summary row 188.8, a two column grid 168 tall and a detail 116 tall.
- The tabs are the categories table's ([content.md](content.md), Recipes), stepped by the right stick's flick (`[` and `]`) from either half and picked by the pointer. A step scrolls the grid to its top and makes the tab's first recipe the focused one, so the detail follows. A focus on a cell moves to that first cell, one on the toggle or a slot stays. While any label would not draw whole beside its icon, every tab draws its icon alone, centred, shrunk to the tab where the tab is narrower than the icon (`icons_alone_when_cut`).
- The grid: the tab's recipes in data order, those no hand makes included, as icon cells with the craftable mark of the recipe browser. Unlocked only (on at a session's start) hides the locked ones, and turned on it moves the detail off a recipe it hides to the first cell shown, or to nothing on an empty grid. A graph step in the detail opens the recipe's tab, Unlocked only off for a locked recipe.
- Tooltips and the info panel dock beside the view's panel, not beside a half (Widgets). At 1080p the view leaves no room beside it, so they go under or over the focused widget, inside its own half.
- The halves are two panels in the view's: the focus wraps inside each, and Right in the inventory half or Left in the schematics half with nothing ahead in that half's row crosses the seam to the nearest widget ahead (`crafting_seam_target`). `Ui_State.crafting_half` follows the focus. The inventory binding opens on the first stack of the selected toolbar slot's kind, C on the focused recipe's cell (else the first, else the toggle).
- Y (L5, R on the keyboard) assigns (0278) on its release: it names the focused slot's item, or on the schematics half the focused available recipe's first output, on the active toolbar's selected slot (`Toolbar_Assign_Command`, [hud.md](hud.md), Toolbars) and toasts which slot ("Log on slot 3"). An empty slot and a locked recipe name nothing. Held `TOUCH_HOLD_SECONDS` (0.25 s) Y opens the toolbar edit mode instead and its release assigns nothing (0279, `advance_button_hold`; a release before that assigns at once). The info panel does not open here; an item slot keeps its delayed tooltip, and the configure pop-up, its own screen, keeps Y's info panel. On touch the row's Assign names the tapped slot's item or the selected recipe's output, and its long press opens the edit mode. The glyph bar reads "Assign, hold to edit toolbars" while Y would name something, else "Hold to edit toolbars".
- On the inventory half the slots work as in Item slots. On the schematics half A crafts one, R1 with A five and L1 with A the most (Recipe browser), and the context action (X, F) clears the queue (Crafting queue). Cancel last is only the touch row's button. The glyph bar and the touch row are the focused half's: on the schematics Craft, Craft 5 and Craft max on a cell (Select elsewhere), Clear queue, Tabs and Close.

### Configure pop-up

Configuring an item is a modal moment (0202, `configure_screen` in `ui_inventory.odin`). On the crafting view's inventory half, with an empty hand and the highlighted slot holding an item whose record is `configurable` ([content.md](content.md), Items), the context action reads "Configure" in the glyph bar instead of "Sort" and opens the pop-up instead of sorting; on touch the row's Configure takes Sort's place. The highlighted slot is the focused one with a gamepad or the keyboard, the hovered one with the pointer, and on touch the tapped one (the active slot). An item whose configuration the session lacks (a foundation outside a field session, which has no block lists) offers Sort.

- A screen pushed over the crafting view (`Screen.Configure`, keeps the simulation running): a centred panel titled after the configuration ("Foundation blocks"), its rows, and Close. Back, Close and a tap or click off the panel close it; the view under it does not run while it is open and focuses the slot that opened it again on return (`Configure_Popup.return_focus`).
- The rows are chosen by the item's `Item_Configuration`; a later value adds a case to `configure_screen`, not a mechanism. The settings apply to every item of the kind, not to the highlighted stack.
- Foundation block (0193): a "Block size" label over a strip of the content's sizes (1x1, 2x2, 5x5, 10x10) and a "Block height" label over its heights (1 high, 2 high, 5 high), the current choice underlined in the accent colour. Each strip is a tab strip in its focus mode (`ui_tabs`, `.Focus`): up and down move between the strips and Close, left and right step a strip, Confirm on a strip steps it forward and wraps as a settings choice does, the pointer and a tap pick a choice. A pick queues a `Foundation_Block_Command` (lockstep state, as a recipe choice is), and the strips show the command on its way until the tick applies it. The glyph bar reads Confirm "Pick" on a strip and Confirm "Close" on the Close button, and Back "Close".

### Toolbar edit

Rearranging the toolbars' shortcuts (0279, after Techtonica, `ui_toolbar_edit.odin`), a screen pushed over the crafting view (`Screen.Toolbar_Edit`, keeps the simulation running) by Y held there (Crafting view).

- A centred panel titled "Edit toolbars", 728 wide, with a row of eight cells per toolbar, row 0 at the bottom and the active toolbar as on the HUD. A cell draws as a HUD toolbar slot: the kind's icon, its inventory count and the shade while the inventory lacks it; its tooltip names the kind. The HUD draws under the backdrop and shows each change once the tick applies it.
- The cursor starts on the selected slot of row 0. The d-pad moves it: Left and Right wrap along the row, Up goes to the row above (nothing on the top row), Down to the row below. Down on row 0 rolls the rows as a carousel: the top row's toolbar comes down to row 0, the others move up, and that toolbar becomes the active one (`Active_Toolbar_Command`). The focus never leaves the grid (the screen takes the step, `step_toolbar_edit_cursor`).
- A on a named cell picks the shortcut up: the cell shows the hole and the shortcut follows the cursor as a held stack does. A on an empty cell moves it there; on another kind the two swap and the one from the cell is held, the hole staying where the first came from; on the same kind they merge, the hole cleared; on the hole it goes back. The glyph bar reads Pick up, Place or Swap.
- X clears the held shortcut, else the cursor's slot ("Clear, hold for the row"). Held `QUICK_MOVE_REPEAT_SECONDS` (0.5 s, twice the hold that opens the mode: it clears up to eight shortcuts and nothing undoes it) it clears every slot of the cursor's row, once; the press that cleared a held one clears no row.
- B ("Done"), Pause and a tap off the panel close it. A shortcut still held stays where it was: a pick up sends nothing, so the simulation always holds the grid with the held shortcut on its origin, and closing by any path sends nothing.
- The bumpers give A and a click no meaning here, and the triggers, the window keys and E do nothing; Y opens no info panel.
- The pointer moves shortcuts as it moves stacks (Slot_Drag): a drag past the slop picks one up and its release moves, swaps or merges on the cell under it, or puts it back off the cells. With nothing held a click without moving only focuses; with one held it drops or swaps on the cell as A does, and off the panel it closes the mode. On touch a tap acts as A, and the row shows Clear and Done.
- Every change is a `Toolbar_Assign_Command`: a move and a swap queue two in one frame, which one record carries, so every machine applies both at the start of one tick; a merge queues one. The grid shows the commands on their way (`shown_toolbars`).

### Recipe browser

The browser of the recipe picker and the station mode (`recipe_screen`). Its window became the crafting view's schematics (0277), and with neither mode it closes.

- A name sorted list with the letter wheel (left pad; keyboard letters jump too, except the menu keys A C D E F Q R S W), filters and a detail panel. The categories are a focusable row under the title row (`ui_tabs` with `.Focus`): up from the list reaches it, left and right change the category, and the tab step (the right stick's flick, `[` and `]`) changes it wherever the focus is, in every mode (`recipe_category_tabs`, 0276). A change drops the tag filter.
- Filter "Can craft now" (0091). Both modes list unlocked recipes only.
- Picker mode: from an assembler's panel it lists what that machine makes, and a choice sets the recipe and returns to the panel. It keeps its own title and lies outside the window carousel.
- Station mode (0196): a crafting station's panel (the stone cutting table, or the pod's crafting bench with the `hand` maker, 0198, `machine_is_crafting_station`; opened with the inventory binding as any panel) is the browser itself (`open_station_recipes`): titled with the station's name, outside the window carousel, without the "Unlocked only" toggle, with category tabs only for the categories holding its maker's recipes and opening on the first (`station_categories`), listing the unlocked recipes of its maker (`station_filter`). Craft, Craft 5, Craft max and Cancel last work as below, the crafts going into the hand queue with the station's maker added (`player_craft_makers`, [content.md](content.md), Hand crafting); Back closes the browser and the station's panel together. Leaving the mode (Back, the pause menu's Resume, the station gone) gives the browser back the filter it had before (`close_station_recipes`).
- Craftable means the queue would accept it now, intermediates included (0156): the "Can craft now" filter, the row mark and "Can craft N" ask the planner (`planned_crafts`, `crafting.odin`) after what the queue holds, N the most crafts it accepts, at most `PLANNED_CRAFT_COUNT_LIMIT` (999). Each ingredient row's number is what the queue leaves for this recipe (the inventory after the queued runs and the recipe's earlier ingredients); its colour says whether that covers the need (the accent), whether the rest is craftable from held materials ("0 / 3 Iron gear, craftable", the dim text colour), or whether it is missing (the danger colour). The plans are kept on the browser and planned again only when the inventory, the queued runs, the front's state, the unlocked recipes or the focused recipe change (`Recipe_Plans`).
- Detail: each ingredient as "13 / 5 Stone" (what the queue leaves, per craft) in its colour above; "Can craft N" (accent from 1, dim at 0); products as "4 × Plank, 12 held"; then the first output's description, dim (0070). Unlocked rows end with the first product's held count, dim at 0. A fluid only recipe and a locked silhouette show none of these.
- A (Craft) queues one craft, with R1 or Left Control held (Craft 5) five, with L1 or Left Shift held (Craft max) the most the planner accepts (`planned_craft_count`, at most 999, and one when it accepts none, so the refusal toasts), and X or F (Cancel last) takes one off the newest run (0276). A click on a row reads the modifier on its release. In the picker the modifiers do nothing.

Crafting queue (0138):

- Crafts queue all or nothing, planned against the inventory plus what earlier runs make minus what they use; missing hand craftable intermediates queue first ([content.md](content.md), hand crafting). Otherwise nothing queues and a toast names the first shortage ("Missing 4 Iron plate"), a cycle ("Cannot plan: X is made from itself") or depth past `HAND_CRAFT_PLAN_DEPTH` (16, "Cannot plan: too many steps to make X").
- At most `HAND_CRAFT_QUEUE_RUNS` (64) runs of a recipe and a count; crafting the last run's recipe grows it. Cancel last refunds only the craft in progress.
- Clear queue (0277, the crafting view's context action and touch button, `Clear_Craft_Queue_Command`) empties every run, all or nothing: it refunds only the craft in progress, nothing for one started under free crafting, and when those ingredients do not fit it changes nothing and toasts "Inventory full".
- The station browser's filter column and the crafting view's header read "Crafting  20", the crafts over all runs, in the accent while the queue waits.
- A front craft missing an ingredient spent or dropped after queuing waits; the next queue action of any recipe repairs it when the inventory can make the item, queuing the makers ahead; cancelling it removes the runs behind first. The HUD shows the queue ([hud.md](hud.md)).

### Technology screen

The browser's shape: a sorted list with the letter wheel and a "Hide researched" toggle, a detail panel with status, cost, description (dim), prerequisites and unlocks; Confirm queues research. An infinite technology shows "Level n", the next level's cost and the effect per level.

### Other screens

- **Machine panel**: the machine's description dim under its name, wrapped, which makes the machine side scroll sooner.
- **Charge controller** (0198, the oxygen generator until 0358): the pod's controller's panel is the machine panel with one fitted row under the description, "Cradle supply: unlimited" (`charge_controller_panel_region`). The pod's locker is a chest's panel with Take all and Store all.
- **Statistics** (0028): Production (a 1, 10 or 60 minute window, items by produced per minute with consumed beside, a detail row with the machines making and using the item and the voided total), Shipments (launches newest first with cargo).
- **Power** (P, the pause menu's Power row): the power overview, the networks on the left and on the right the focused network's figures, its limiting cables (0369, under its Power line, so they stay at the smallest size where the largest consumers give way) and its generators and consumers grouped by machine type ([fluids.md](fluids.md), Power); the carousel's sixth window.
- **Bottleneck overlay**: a marker over every machine, green working, yellow output full, red starved of input, fuel or power, grey idle (colour blind: blue, orange, white, black), near constant screen size beyond 15 blocks (`marker_size`).
- **Map** (0038, View or M): the explored area as one 256 by 256 image at 1 to 16 blocks per pixel, the surface block tinted half way to its biome's `map_color` (0058), with the player, machines and the prospecting layers (vein footprints, magnetometer readings, core samples, seismic circles). The legend lists the palette's marker colours, then the image's biomes, the player's in the accent marked "you are here", in a second column when short of height.
- On the map, biomes are sampled only when the frame moves or zooms, and a pan keeps the pixels it had. The right stick (up and down held, or a flick left or right), `[` and `]` or the wheel zoom (0276), left stick or drag pans. A diagonal flick zooms one level, the flick's way, and starts the held stick's repeat wait.
- **Launch pad** (0040, 0041): Rocket (part slots, cargo, Assemble, Launch), Contracts (credit, open contracts oldest first with deliveries, time left or Late, late share, reward), Catalogue (a button per entry; an order the credit does not cover, counting unserved orders, is refused with a toast).
- **Journal**: the chapters, Contracts (credit, fulfilled and late tally, open contracts over the message log), Notes (0070: unlocked notes newest first with "n more to find" or "Every note found", the focused note on the right, "Nothing noted yet" without). After the last quest the last chapter starts with "Contracts continue". The log frames Mission Control's rows like its panel.
- **New world**: the name and the seed (the keyboard only for these two fields, Randomise beside the seed), then the settings, each a choice that Confirm or a click steps forward: Planet (one entry for now, named by the string `planet_<id>`), Planet radius (the planet's presets, 4, 8 and 16 km for home; a new planet starts at its default), Terrain detail (the sample spacing, 1, 0.5 or 0.33 m), Water (the water model, Teleport or Bodies, Teleport by default, with the value's one line description dim under the row), Mode (peaceful, survival, creative; every mode plays as peaceful for now, as its tooltip says), Keep inventory (a toggle), then veins, richness, research cost, byproducts, all recipes and day length ([content.md](content.md), Planets). The rows scroll under the heading when the panel is clamped to the safe area; the audit walks the focus over every control at every size.
- **Load**: name (marked "(other build, cannot load)"), seed, played, last saved; Delete beside Back (or X) acts on the last focused save, loadable or not.
- **Title**: a sky coloured backdrop with name and version, since a world view would need a session. Continue (with a save), New world, Tech demos (0302), Load, Multiplayer, Settings, Quit.
- **Multiplayer** (0188, `ui_multiplayer.odin`): the games the LAN answered within the last three seconds, world, host, players and build per row, in the order they first answered, at most 64 (`MAXIMUM_LAN_GAMES`); Confirm or a click on a row joins it through the `--join` path, with the existing joining notice and failure toast; a join asked while one runs toasts "Already joining a game". A game of another build is greyed and marked "(other build)", and Confirm on it only toasts that its host refuses the join. "Looking for games on the local network" while the list is empty. Under the list the "Join by address" field (the keyboard's one use here) with Join beside it, for networks that drop broadcasts and for the phone, which needs an IP address; then Back. The list follows the answers between frames while the screen shows, and the query stops when it closes ([architecture.md](architecture.md), Multiplayer). The audit draws it empty, with three games of the longest texts an answer carries (one of another build), and with the address under either keyboard.
- **Tech demos** (0302, `ui_tech_demo.odin`): the list of the tech demos, one button per demo (today Water, which opens the Tech demo screen), then Back. Back on the Tech demo screen returns here. Navigated as every title screen; the audit draws it and walks its focus.
- **Tech demo** (0291, `ui_tech_demo.odin`): the water tech demo's menu ([build.md](build.md), The water tech demo): three choices that Confirm or a click steps forward, Water model (Teleport pressure, Bodies), Planet radius (the default planet's presets) and Start point (Home, Spring), then Start, which asks the frame loop for the demo session, and Back. Navigated as every title screen; the audit draws it and walks its focus.
- **Split screen** (0178, [input.md](input.md), Split screen): every viewport runs its own HUD and screens in its rectangle, laid out at the viewport's size like a screen of its own; the UI follows the height, so a quarter of 1080p lays out as 1080p at half the pixels, and a viewport narrower than 16:9 scales its UI down until the 16:9 layout fits its width (`viewport_ui_scale`). A guest's pause menu is under Architecture, Screens. A viewport whose pad was lost shows "Controller lost: press Start" over its HUD, and one whose player's join tick has not run shows "Joining". The touch overlay draws only while one viewport plays.

### Touch layout editor

`ui_touch_layout_editor.odin` (0121); what it edits and saves: [touch_overlay.md](touch_overlay.md).

- A dimmed backdrop with the layout full size at the overlay's scale and opacity; each button and the stick a focusable widget with a handle at its top left, the selected one outlined in the accent. A floating stick sits mid half and cannot move; the look is not shown.
- A central panel: the layout's and the element's names, four rows (a button: Size and Opacity steppers, Control, Double tap latches; the stick: Radius and Opacity steppers, Fixed in place), Name with Save as, a row of Save, Delete and Reset to Default, and Close.
- Pointer: a press selects and grabs, a drag moves; the panel shields elements under it. Gamepad: one focus scope over the screen; Confirm selects the focused element, the d-pad or arrows move it by 10 reference pixels while it holds the focus, LT and RT (Q and E, 0276) resize the selection anywhere. B or Close leaves and drops an unsaved draft.
- Save and Delete on Default toast that Default cannot change.

## Text and theme

Text is TrueType (0077), rasterised at `round(text_size * pixels_per_unit)` pixels per size and drawn at whole pixels, so stems are even at every scale; headings and the HUD quest title are bold. The families live in `data/fonts/<id>/` with their licences, listed in `data/fonts/fonts.sjson` (technical faces first with Exo 2 the default, plain faces, then monospace for the diagnostics). Every text with the multiplication sign comes from the string table, so every font loads it; `test_shipped_fonts_have_every_string_glyph` checks each shipped font covers the table's non ASCII code points.

The theme is `data/ui/theme.sjson` (0071, `ui_theme.odin`); fonts and theme are presentation data for hot reload.

- Keys: colours `[red, green, blue, alpha]` named in `ui_theme_color_names`; `border`, `corner`, `focus_pulse` in UI units; `palettes = {default = {...} colour_blind = {...}}` with `palette_color_names` (four bottleneck states, eight map colours), each set kept apart (`test_palettes_colour_every_marker_apart`).
- A missing key keeps its built in default, so a file that sets nothing changes nothing. An unknown key, a wrong type or a value out of range refuses the file by name: at start the game exits, on a reload it keeps the old theme. Alpha 0 turns an element off.
- The theme lives in `Ui_State.theme`; screens naming `UI_TEXT_COLOR`, `UI_PANEL_COLOR`, the other colours and `UI_BORDER` read package variables `apply_ui_theme` sets. Layout sizes (`UI_ROW_HEIGHT`, `UI_SLOT_SIZE`, `UI_PADDING`, `UI_GAP`, the text sizes) and font roles are compile time constants.
- Panels: a fill, an edge in `panel_edge` and a highlight one border inside, corners cut by `corner` as square notches, built from pieces that never overlap since colours may be translucent. Tooltips the same in `tooltip` with an accent edge; toasts a plain `toast` fill.
- Widgets are `widget`, `widget_hover` under the pointer, `widget_active` while Confirm or the pointer is held on them. The focus outline is `focus`, 4 units plus `focus_pulse` times a 1.4 second cosine pulse, growing inwards; the audit runs the pulse at both ends.
- Tabs draw an optional icon, the selected label in the accent over a 4 unit underline, and a `divider` line. Sliders and on toggles fill in the accent.
- Under the default palette map machine dots take their item category's marker colour; every shipped machine item is in the machine category, so they share one colour.

Icons:

- UI icons: `data/ui/icons/<name>.png`, 16 by 16 RGBA, one per `Ui_Icon` (names in `ui_icon_names`), packed into the UI atlas. Bumpers read L1 and R1, triggers LT and RT, sticks L and R (0095).
- Item icons: `data/textures/items/<item id>.png` (16 by 16 RGBA, 0060) in the item atlas, drawn through `draw_item_icon`; without a file the placed block's tile, else a coloured square with two letters. On belts and the ground an icon is a 0.4 block camera facing quad, else a small cube in the category colour.
- The shipped icons are placeholders from `tools/make_placeholder_textures.py` ([content.md](content.md), Textures).

## On-screen keyboard

Rule: a text field opens a keyboard entry (`open_keyboard`); the Text entry keyboard setting picks the system keyboard where one exists (the default) or the game's keys (0133).

- A field takes printable ASCII, digits alone (a seed) or a number's characters (`Text_Field_Characters`). Names are capped at 32 characters, seeds at 20 digits (0024), any field at 512 (`TEXT_FIELD_CAPACITY`).
- A physical keyboard types into the field; Enter finishes, B and Escape (Pause) are Done.
- The game's keys: a grid under the field (`1234567890`, `qwertyuiop`, `asdfghjkl`, `zxcvbnm`, `-_./`) with large shift, space, backspace and done keys, driven by focus and pointer (the `/` serves paths such as the export directory). A types the focused key, X backspaces, Y toggles shift, B is done. The panel shows only the field and the keys.

The system keyboard (`Keyboard_State.system`, from `Ui_State.system_keyboard`):

- The panel shows the field alone; the glyph bar shows Keyboard (A), Delete (X), Done (B); text takes the physical keyboard's path (`typed_text`, `backspace_key`, `enter_key`). Enter, B, Pause or a tap outside the field end the entry; a tap on the field or Confirm shows the keyboard again, since the phone's Back hides the IME and Steam may close its keyboard on its own.
- The frame loop shows it once the field was drawn and hides it however the entry ended (`sync_system_keyboard`, pure `system_keyboard_change`), handing on the field's rectangle (`Keyboard_State.field_rectangle`) in window coordinates.
- Android (`system_keyboard_android.odin`): the IME via `ANativeActivity_showSoftInput` and `ANativeActivity_hideSoftInput`; key to text: [android.md](android.md), Keyboard.
- Linux (`system_keyboard_linux.odin`): Steam's keyboard when `SDL_ENABLE_STEAM_SCREEN_KEYBOARD` or `SteamDeck` is 1, opened with `steam://open/keyboard?XPosition=<x>&YPosition=<y>&Width=<w>&Height=<h>&Mode=0` and closed with `steam://close/keyboard` through SDL's `OpenURL`. Its keys arrive as GLFW events; one pressed and released within a poll still counts as down (`add_pressed_keys`), so Backspace and Enter reach the field.
- Windows and Linux outside Steam have none (`system_keyboard_windows.odin`). The log says at start whether one is available. Choose `game` for an IME whose extract mode covers the field or a Steam session that ignores the deep link.
