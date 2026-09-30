# 0122: Haptics on the phone

Status: implemented

## Goal

The last phase of the Android spitball approved on 2026-09-29 ("then the editor and haptics"). The game's haptic requests (`Haptic_Request`, `haptic_request_for` in `ui_prospecting.odin`: the magnetometer buzzes harder as the player nears iron) reach nothing on Android, since only the SDL3 backend rumbles and the Android build has no SDL. The phone's vibrator plays them.

## Change

- `src/platform_android.odin` (or a new `src/haptics_android.odin`, `#+build linux:android`): the vibrator through JNI. `Android_Native_Activity` already carries `vm` and `clazz`. Declare the slice of `JNINativeInterface` and `JNIInvokeInterface` the calls need, at the indices of the NDK's `jni.h` (`~/opt/android/sdk/ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include/jni.h`, checked against the copy the CI runner has, same NDK version): `AttachCurrentThread` once on the game thread, then `FindClass`, `GetMethodID`, `GetStaticMethodID`, `CallObjectMethod`, `CallStaticObjectMethod`, `CallVoidMethod`, `CallBooleanMethod`, `NewStringUTF`, `DeleteLocalRef`, `ExceptionCheck` and `ExceptionClear`. At start: `activity.getSystemService("vibrator")` (the `Context.VIBRATOR_SERVICE` string), kept as a global reference; `hasVibrator` and `hasAmplitudeControl` logged once. Each request with strength above 0 plays `VibrationEffect.createOneShot(100, amplitude)` (the SDL backend's `HAPTIC_RUMBLE_MILLISECONDS`; amplitude 1 to 255 from the strength, `DEFAULT_AMPLITUDE` when the vibrator has no amplitude control); a strength of 0 after a running one calls `cancel()`. Every JNI call clears a pending exception and logs once.
- `tools/android/AndroidManifest.xml`: `<uses-permission android:name="android.permission.VIBRATE" />`.
- The raylib backend's frame applies the request the way the SDL3 backend does (`apply_sdl3_haptics`): on Android through the vibrator, elsewhere nothing, as now.
- `doc/build.md` Android app section: the vibrator, the JNI slice and the permission; the "what the Android build lacks" bullet loses rumble. `doc/input.md`: haptics on Android.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`. A test for the amplitude mapping (0 → cancel, 0.5 → 128, 1 → 255) and the JNI index table against the numbers written in the work item's Implemented section from `jni.h`.
- The user, on the phone: the magnetometer buzzes near iron, stronger closer.

## Implemented

- `src/haptics_android.odin` (`#+build linux:android`): the vibrator through JNI, `start_vibrator`, `apply_vibrator_haptics`, `stop_vibrator`. `src/haptics_desktop.odin` (`#+build !linux:android`): the no-op. `src/loop.odin`: `Frame_State.vibrator`, started and stopped in `run_game`, applied in `update_frame` on the raylib backend. `src/input_actions.odin`: `vibration_amplitude` and `HAPTIC_RUMBLE_MILLISECONDS` (moved from `input_sdl3.odin`, which the Android build leaves out). `src/jni_indices.odin` and `src/jni_indices_test.odin`: the table slots and their test; the amplitude test is in `src/input_actions_test.odin`. `tools/android/AndroidManifest.xml`: the VIBRATE permission.
- JNI indices, counted from 0 over the members of `struct JNINativeInterface` in `jni.h` of NDK 27.3.13750724 (`reserved0` to `reserved3` are 0 to 3): FindClass 6, ExceptionClear 17, NewGlobalRef 21, DeleteGlobalRef 22, DeleteLocalRef 23, GetMethodID 33, CallObjectMethodA 36, CallBooleanMethodA 39, CallVoidMethodA 63, GetStaticMethodID 113, CallStaticObjectMethodA 116, NewStringUTF 167, ExceptionCheck 228. `struct JNIInvokeInterface` (`reserved0` to `reserved2` are 0 to 2): AttachCurrentThread 4, DetachCurrentThread 5.
- Deviation: the `A` variants (arguments as a `jvalue` array) instead of the variadic `CallObjectMethod`, `CallBooleanMethod`, `CallVoidMethod` and `CallStaticObjectMethod`, so no call from Odin goes through C varargs.
- Deviation: the thread attaches before every use rather than once, because raylib's `GetCurrentMonitor` (`rcore_android.c`) detaches the calling thread and the game calls it at start and in the display diagnostics. `stop_vibrator` detaches at the end of `run_game`, because the activity can end while the process lives and an attached thread must detach before it exits.
- Deviation: a failed call logs once and turns the vibrator off for the run, so a call that keeps throwing does not log every frame.
- Checked: the APK built by `./build.sh android` lists `android.permission.VIBRATE` (`aapt dump permissions`).
