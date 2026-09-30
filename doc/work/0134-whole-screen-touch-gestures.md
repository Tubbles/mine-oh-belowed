# 0134: Tap and hold anywhere on the screen, without the trigger and shoulder buttons

Status: todo

## Goal

Asked on 2026-09-30: "I want the whole screen to react to taps and tap-and-hold for placing and mining blocks, respectively, right now it seems like its only the right hand side that has this behavior? With this i think we can remove the L2 and R2 overlay buttons completely? Along with the L1 and R1". Today (0118) the tap scheme runs on the free look half only: the left half is the floating stick's, so a tap there does nothing. LT and RT (place and mine) duplicate the tap and the hold, LB and RB (`Hotbar_Previous`, `Hotbar_Next`) duplicate tapping a hotbar slot (0119).

## Change

- Every finger that lands on free screen (not on a button, not on a hotbar slot, not inside a static stick's base) is undecided at first (`Pending`), on both halves. It becomes a drag once it moves past `TOUCH_TAP_SLOP`: the stick when it landed on the stick's side and the stick is free (centred where it landed, taking the whole drag so far, as the look drag does today), else the look drag. It becomes a hold once it rests `TOUCH_HOLD_SECONDS` inside the slop (Mine through `hold_control`, aimed at the finger), and a lift before either is a tap (Interact or Place through the look element's controls, as today). So the left half gains taps and holds, the stick starts after the slop instead of at the landing, and a second finger on the stick's side while the stick is held taps, holds or looks instead of reading nothing. A static stick (0120) keeps taking only the touches inside its base; the rest of its half is free screen like the other.
- The `crosshair` scheme (`settings.touch_interaction`) keeps the same gestures and changes only the aim: the hold and the tap act at the view's centre instead of the finger. So neither scheme needs a trigger button.
- `data/touch_overlay.sjson`: the LT, RT, LB and RB buttons leave the Default layout. The controls stay known (`touch_overlay_control_from_name`), so a user layout that has them still loads and the editor can still rebind a button to them; the `look` element's `hold_control`, `tap_interact_control` and `tap_place_control` are unchanged. The tests that count or place the Default layout's elements follow.
- The overlay's drawing changes nothing but the four buttons gone. The HUD's mined block ring (0118) shows for holds on either half.
- Docs: `doc/input.md` (Fingers, Tap to interact, the layout description, the table row of LB and RB and LT and RT on touch), `doc/ui.md` where the touch layout is described, `DESIGN.md` Input paragraph (the overlay no longer copies GameNative's button layout in full), `doc/log/2026-09-30.md` with the assumptions: the stick's slop start, the hold on the stick's side (a thumb resting a quarter second before pushing mines once under it; to be judged on the phone), the crosshair scheme's aim.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`. Tests (`touch_overlay_test.odin`, the frame driven tests of 0118 to 0120 as the pattern): a tap on the left half places; a hold on the left half mines and aims at the finger; a finger on the left half that moves past the slop drives the stick with the whole drag so far and never taps; a second finger on the left half while the stick is held becomes the look drag; a tap outside a static stick's base on its half places; in `crosshair` a hold aims at the view's centre; the Default layout has no LEFT_TRIGGER, RIGHT_TRIGGER, LEFT_SHOULDER or RIGHT_SHOULDER button, and a user layout with an LT button still loads.
- The user, on the phone: tap and hold on the left of the screen to place and mine, walk with the stick as before, sprint over the rim, switch slots by tapping the hotbar.
