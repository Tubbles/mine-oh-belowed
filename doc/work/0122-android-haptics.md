# 0122: Haptics on the phone

Status: todo

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
