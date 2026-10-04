# 0235: Android follows the sensor between the two landscapes

Status: landed (2026-10-04, "Let Android turn the game between the two landscapes (0235)", 453b1fe, APK 489 sent the same day; done by the main agent as trivia (one manifest attribute, the doc and the log); from the user on the phone: "On android it needs to allow for reversed landscape, my gamesir x2 connects in the opposite orientation, so the game is now upside down"; the manifest locked the activity to `landscape`, one of the two)

## Goal

The game on the phone turns with the phone between the two landscape orientations, so a clip controller whose USB plug puts the phone the other way up (the user's GameSir X2) shows the game the right way up.

## Controls

No binding changes. The touch layout and the HUD keep their places relative to the screen, which the system turns as a whole.

## Change

- `tools/android/AndroidManifest.xml`: `android:screenOrientation="sensorLandscape"` in place of `"landscape"`. The activity already declares `orientation|screenSize` in `configChanges`, so the 180 degree turn reaches raylib's native glue as a configuration change on the same surface size, with no activity restart.
- Docs: `doc/android.md` (the manifest line), `doc/log/2026-10-04.md`.

## Verify

- `./build.sh check-android`, `./build.sh android` (the APK builds and installs).
- The phone: with the GameSir X2 clipped on, the game is the right way up; turning the phone over turns the game; portrait is still refused.
