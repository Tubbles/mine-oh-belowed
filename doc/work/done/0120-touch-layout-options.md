# 0120: Static stick and double tap toggles in the touch layout

Status: implemented

## Goal

Two Bedrock options approved on 2026-09-29 and left out of 0115: a static joystick for people who want the stick in a fixed place, and hold versus toggle per element in the layout data (Bedrock's double tap sneak to toggle it), on top of the `sneak_hold` and `sprint_hold` settings, which apply to every device.

## Change

- `data/touch_overlay.sjson`, stick element: `static = false` by default. A static stick has `anchor` and `position` like a button and draws its base ring at rest; a touch that begins inside its base circle drives it, centred on the base, a touch elsewhere on its half is ignored (it is not the look zone). `resolve_touch_overlay_stick` validates the keys (a static stick needs anchor and position, a floating one refuses them).
- Button element: `double_tap_toggles = false` by default. When true, a second tap on the button within `TOUCH_DOUBLE_TAP_SECONDS` (0.3) latches it down until the next tap; a single tap presses it as today. The shipped layout sets it on B (Sneak), so double tapping B toggles sneak while the sneak setting is Hold. `draw_touch_overlay_button` draws a latched button filled like a held one.
- `doc/input.md` and the comment block at the top of `data/touch_overlay.sjson`: both keys.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`. Tests: a static stick reads a touch inside its base and ignores one outside; a double tap latches B and the next tap releases it; a single tap presses and releases; a floating stick with a position fails to load with the element named.

## Implemented

- `src/touch_overlay.odin`: element keys `static` and `double_tap_toggles`. `resolve_touch_overlay_stick` refuses anchor and position on a floating stick and requires them on a static one. `classify_touch` ignores a touch on the stick's half outside a static stick's base (`stick_reaches`), and `touch_origin` puts a static stick's drag origin at the base centre (`static_stick_centre`). `Touch_Overlay_State` gains `latched` (a bit set over the element index) and `double_tap` (the last lift of a toggling button and the frame time since, `advance_double_tap`); `touch_down_toggles` latches or releases on a landing, `lifted_button_arms_double_tap` arms on a lift, and `touch_overlay_output` presses latched buttons (`latched_button_reads`). `src/hot_reload.odin`: `replace_frame_content` releases the latches. `draw_touch_overlay` draws a static stick's base with a centred knob while no finger holds it; a latched button draws filled through the output like a held one.
- `data/touch_overlay.sjson`: both keys in the comment block, `double_tap_toggles = true` on B. `doc/input.md`: the options and the validation.
- Deviations:
  - A zero position counts as missing: the configuration loader leaves an absent key at zero, so `position = [0, 0]` on a floating stick is accepted and on a static one refused. A stick centred on a screen corner is of no use anyway.
  - A layout holds at most 64 elements (`TOUCH_OVERLAY_ELEMENT_CAPACITY`), the size of the latch bit set; the file is refused beyond that.
  - The touch that releases a latch still holds the button until it lifts, and neither the latching nor the releasing touch arms a new double tap.
  - Latching works only while the sneak setting is Hold (`Touch_Interaction_Frame.double_tap_latches`, from `settings.sneak_hold`); in Toggle a double tap is two taps and an existing latch is released. In Toggle a latch would toggle sneak on and off and then swallow the next tap's edge.
  - Only a tap (down less than `TOUCH_HOLD_SECONDS`) arms the double tap, so a long press followed by a quick one does not latch.
  - A data reload releases every latch and the double tap (`release_touch_latches` in `replace_frame_content`, `src/hot_reload.odin`), since the latches index the old layout's elements.
  - `static` on a button or look and `double_tap_toggles` on a stick or look are accepted and ignored, like the other kind specific keys.
- Tests: `test_a_static_stick_reads_a_touch_inside_its_base_and_ignores_one_outside`, `test_a_double_tap_latches_b_and_the_next_tap_releases_it`, `test_single_taps_on_b_press_and_release`, `test_double_taps_latch_only_while_the_sneak_setting_is_hold`, `test_a_data_reload_releases_the_latches`, `test_a_long_press_on_b_then_a_quick_press_does_not_latch`, three stick cases in `test_touch_overlay_errors_name_the_element` (`touch_overlay_test.odin`).
