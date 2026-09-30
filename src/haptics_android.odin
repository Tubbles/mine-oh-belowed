#+build linux:android
package game

import "platform"

// The phone's vibrator through JNI (work item 0122, doc/android.md,
// Haptics), through the platform package's helpers (jni_android.odin),
// which attach the game thread first and leave every local reference to
// be deleted by hand.

// VibrationEffect.DEFAULT_AMPLITUDE, for a vibrator without amplitude
// control.
VIBRATION_DEFAULT_AMPLITUDE :: -1

Vibrator_State :: struct {
	// Found at start and no call has failed since.
	available:         bool,
	amplitude_control: bool,
	// A vibration was started and not yet cancelled.
	vibrating:         bool,
	// Global references: the Vibrator service and the VibrationEffect class.
	vibrator:          rawptr,
	effect_class:      rawptr,
	// Method ids, valid for the process.
	vibrate:           rawptr,
	cancel:            rawptr,
	create_one_shot:   rawptr,
}

// activity.getSystemService("vibrator"), a local reference.
jni_vibrator_service :: proc(calls: ^platform.Jni_Calls) -> rawptr {
	context_class := platform.jni_find_class(calls, "android/content/Context")
	get_system_service := platform.jni_method(calls, context_class, "getSystemService", "(Ljava/lang/String;)Ljava/lang/Object;")
	name := platform.jni_new_string(calls, "vibrator")
	arguments := [1]platform.Jni_Value{{object = name}}
	service := platform.jni_call_object(calls, platform.GetAndroidApp().activity.clazz, get_system_service, arguments[:], "getSystemService")
	platform.jni_delete_reference(calls.environment, name)
	platform.jni_delete_reference(calls.environment, context_class)
	return service
}

// The vibrator's method ids and whether it vibrates at all.
find_vibrator_methods :: proc(calls: ^platform.Jni_Calls, state: ^Vibrator_State, service: rawptr) -> (has_vibrator: bool) {
	vibrator_class := platform.jni_find_class(calls, "android/os/Vibrator")
	has_vibrator_method := platform.jni_method(calls, vibrator_class, "hasVibrator", "()Z")
	amplitude_control_method := platform.jni_method(calls, vibrator_class, "hasAmplitudeControl", "()Z")
	state.vibrate = platform.jni_method(calls, vibrator_class, "vibrate", "(Landroid/os/VibrationEffect;)V")
	state.cancel = platform.jni_method(calls, vibrator_class, "cancel", "()V")
	platform.jni_delete_reference(calls.environment, vibrator_class)
	has_vibrator = platform.jni_call_boolean(calls, service, has_vibrator_method, "hasVibrator")
	state.amplitude_control = platform.jni_call_boolean(calls, service, amplitude_control_method, "hasAmplitudeControl")
	return has_vibrator
}

find_vibration_effect :: proc(calls: ^platform.Jni_Calls, state: ^Vibrator_State) {
	effect_class := platform.jni_find_class(calls, "android/os/VibrationEffect")
	state.create_one_shot = platform.jni_method(calls, effect_class, "createOneShot", "(JI)Landroid/os/VibrationEffect;", is_static = true)
	state.effect_class = platform.jni_new_global_reference(calls, effect_class)
	platform.jni_delete_reference(calls.environment, effect_class)
}

// Looks the vibrator up once and logs what it found.
start_vibrator :: proc() -> Vibrator_State {
	environment := platform.jni_environment()
	if environment == nil {
		platform.log_printf("haptics: no vibrator (the game thread could not attach to the Java VM)")
		return {}
	}
	calls := platform.Jni_Calls {
		environment = environment,
	}
	state: Vibrator_State
	service := jni_vibrator_service(&calls)
	has_vibrator := find_vibrator_methods(&calls, &state, service)
	find_vibration_effect(&calls, &state)
	state.vibrator = platform.jni_new_global_reference(&calls, service)
	platform.jni_delete_reference(environment, service)
	if calls.failed != nil {
		platform.log_printf("haptics: no vibrator (%s failed)", calls.failed)
		release_vibrator_references(environment, state)
		return {}
	}
	platform.log_printf("haptics: vibrator %s, amplitude control %s", has_vibrator ? "found" : "absent", state.amplitude_control ? "yes" : "no")
	state.available = has_vibrator
	return state
}

release_vibrator_references :: proc(environment: rawptr, state: Vibrator_State) {
	platform.jni_delete_reference(environment, state.vibrator, platform.JNI_DELETE_GLOBAL_REF)
	platform.jni_delete_reference(environment, state.effect_class, platform.JNI_DELETE_GLOBAL_REF)
}

// A vibration of HAPTIC_RUMBLE_MILLISECONDS at the requested strength,
// renewed every frame; a request of 0 cancels a running one once. A
// failed call logs once and turns the vibrator off for the run.
apply_vibrator_haptics :: proc(state: ^Vibrator_State, request: Haptic_Request) {
	if !state.available {
		return
	}
	amplitude := vibration_amplitude(request.strength)
	if amplitude == 0 && !state.vibrating {
		return
	}
	calls := platform.Jni_Calls {
		environment = platform.jni_environment(),
	}
	if calls.environment == nil {
		calls.failed = "AttachCurrentThread"
	} else if amplitude == 0 {
		platform.jni_call_void(&calls, state.vibrator, state.cancel, nil, "cancel")
	} else {
		play_vibration(&calls, state^, state.amplitude_control ? amplitude : VIBRATION_DEFAULT_AMPLITUDE)
	}
	state.vibrating = amplitude > 0
	if calls.failed != nil {
		platform.log_printf("haptics: %s failed, the vibrator is off", calls.failed)
		state.available = false
	}
}

play_vibration :: proc(calls: ^platform.Jni_Calls, state: Vibrator_State, amplitude: i32) {
	one_shot_arguments := [2]platform.Jni_Value{{long = HAPTIC_RUMBLE_MILLISECONDS}, {integer = amplitude}}
	effect := platform.jni_call_object(calls, state.effect_class, state.create_one_shot, one_shot_arguments[:], "createOneShot", is_static = true)
	vibrate_arguments := [1]platform.Jni_Value{{object = effect}}
	platform.jni_call_void(calls, state.vibrator, state.vibrate, vibrate_arguments[:], "vibrate")
	platform.jni_delete_reference(calls.environment, effect)
}

// At the end of run_game: cancels a running vibration, frees the global
// references and detaches the game thread, which must not end attached
// (the activity can end while the process lives, main_android.odin).
stop_vibrator :: proc(state: ^Vibrator_State) {
	apply_vibrator_haptics(state, {})
	environment := platform.jni_environment()
	if environment != nil {
		release_vibrator_references(environment, state^)
	}
	state^ = {}
	vm := platform.GetAndroidApp().activity.vm
	detach := cast(platform.Jni_Detach_Current_Thread)platform.jni_function(vm, platform.JNI_INVOKE_DETACH_CURRENT_THREAD)
	detach(vm)
}
