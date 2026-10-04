# 0218: Sneak crouches the field player

Status: todo (2026-10-04, user: "lets also make it so 'sneak' is a visible crouching, so we can sneak into 1 meter holes"; folds the field's missing sneak toggle)

## Goal

Sneak on the field is a crouch the player can see: the capsule shrinks to a crouch height so the player fits through a 1 m gap (two cells at the shipped 500 mm spacing), the eye drops with it, and the body is drawn crouched for the other players and the third person camera. Standing up waits for headroom, so a player who releases Sneak inside a tunnel stays crouched until the tunnel opens. Today Sneak only slows the walk (`field_walk_speed`) and descends in fly mode; the capsule is 1.8 m whatever the player does.

## Change

- **The crouch state.** `Field_Player.crouching: bool`, simulation state, set each tick from the sneak state: on while Sneak is on and the player is on foot (not flying); off again only when the standing capsule has room at the feet (`field_capsule_overlaps` with the standing tuning), else it stays on. The sneak speed follows the crouch, not the button, so a player stuck under a ceiling walks at the sneak speed until they stand. Fly mode keeps the standing capsule and Sneak's descent.
- **The sneak toggle on the field (folded bug).** The Accessibility tab's Sneak setting (`sneak_toggles` on the frame, 0074) is honoured by the block world's `tick_player` through `update_sneaking` and `with_sneaking` and by nothing on the field: `tick_field_session_player` and `predict_field_player_motion` build the field input from the frame's held buttons alone (`field_tick_input`). The same two procedures are applied there, so a toggled sneak crouches and un-crouches on the field as it slows the block world's walk; `Player.sneaking` is the truth on the field too.
- **The heights.** Two new keys in `field_player` of `data/game.sjson`: `crouch_height_millimetres` (above two radii, below `capsule_height_millimetres`) and `crouch_eye_height_millimetres` (inside the crouch capsule), shipped so the crouched capsule fits a 1 m gap with the ground tolerance to spare (900 and 750 are the proposal; the design stage checks them against `FIELD_GROUND_TOLERANCE` and the sphere count). The tick's tuning is chosen per player per tick from the crouch flag (a tuning with the crouch heights in place of the standing ones), so every capsule procedure keeps its `tuning` parameter and the step, mantle, ledge and ground probes read the crouched capsule without a change of their own.
- **Lockstep and the save.** The crouch is derived from the input record every tick and from the world's headroom, so the record does not change. `crouching` is saved with the field player and hashed; an old save loads it false, which is right for a player standing in the open, and a saved crouch under a ceiling loads crouched.
- **The eye.** The first person camera reads `field_player_eye` at the crouch height; the eye's height change is eased in presentation over `CROUCH_EASE_SECONDS` (about 0.15 s, frame time, presentation only), so the view dips instead of jumping.
- **The body.** The other players and the third person view draw the crouch: the capsule fallback at the crouch height, and the limb model lowered by the crouch delta with the legs folded at their pivots if `player_limb_angles` and the limb pivots allow it, else the body scaled along the up to the crouch height; the design stage picks and says why. The pose eases like the eye.
- **Out of scope.** The block world's sneak (`player.odin`, the slow walk with the edge check) is unchanged and its docs say so; the touch overlay's Default layout has no Sneak control (0134) and keeps none; no HUD change.

## Controls

No binding changes. Sneak (B, R5 on the gamepad; Left Control on the keyboard since fe4c600; a user touch layout's B) keeps its one meaning in the world: on foot it crouches and slows the walk, in fly mode it descends; the hold or toggle setting applies on the field as in the block world. In the placement editor (0215) B stays Sneak, so a player can crouch while walking round a ghost. This is the keybinding pass: the control's meaning grows a visible effect and gains no second meaning.

## Verify

- Tests (names chosen by the design stage): a crouched player walks through a 1 m gap that stops a standing one; standing up is refused under a 1 m ceiling and succeeds once out; the eye is at the crouch height while crouched; the sneak toggle crouches and un-crouches on the field; the sneak speed applies while crouched after the button is released under a ceiling; the save round trip keeps `crouching` and an old save loads it false; the state hash changes with it; the prediction on a copy matches the tick; a crouched body is drawn lower than a standing one (the capsule fallback and the model).
- The couch: dig a 1 m tunnel into a bank with the pickaxe, crouch in, release Sneak inside (stays crouched), walk out and stand; in multiplayer the other player sees the crouch.
