#+build linux:android
package game

// The phone's vibrator through JNI (work item 0122, doc/build.md, Android
// app). The game thread is raylib's android_main thread, which the VM
// does not know, so every use attaches it first: attaching an attached
// thread only returns its JNIEnv, and raylib's GetCurrentMonitor
// (rcore_android.c, called by current_monitor_size) detaches the thread
// when it is done, so an environment kept across frames could be stale.
// The references and method ids stay valid across a detach. Local
// references are never freed by a return to Java on this thread, so every
// one is deleted by hand.

// VibrationEffect.DEFAULT_AMPLITUDE, for a vibrator without amplitude
// control.
VIBRATION_DEFAULT_AMPLITUDE :: -1
JNI_OK :: 0

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

// jvalue (jni.h): one argument of a Call...MethodA.
Jni_Value :: struct #raw_union {
	integer: i32,
	long:    i64,
	object:  rawptr,
}

Jni_Attach_Current_Thread :: #type proc "c" (vm: rawptr, environment: ^rawptr, arguments: rawptr) -> i32
Jni_Detach_Current_Thread :: #type proc "c" (vm: rawptr) -> i32
Jni_Find_Class :: #type proc "c" (environment: rawptr, name: cstring) -> rawptr
Jni_Get_Method_Id :: #type proc "c" (environment, class: rawptr, name, signature: cstring) -> rawptr
Jni_Call_Object_Method :: #type proc "c" (environment, object, method: rawptr, arguments: [^]Jni_Value) -> rawptr
Jni_Call_Boolean_Method :: #type proc "c" (environment, object, method: rawptr, arguments: [^]Jni_Value) -> u8
Jni_Call_Void_Method :: #type proc "c" (environment, object, method: rawptr, arguments: [^]Jni_Value)
Jni_New_String_Utf :: #type proc "c" (environment: rawptr, text: cstring) -> rawptr
Jni_New_Reference :: #type proc "c" (environment, object: rawptr) -> rawptr
Jni_Delete_Reference :: #type proc "c" (environment, object: rawptr)
Jni_Exception_Check :: #type proc "c" (environment: rawptr) -> u8
Jni_Exception_Clear :: #type proc "c" (environment: rawptr)

// An environment and the first call that failed in a run of calls: after
// a failure every further call does nothing and returns nil.
Jni_Calls :: struct {
	environment: rawptr,
	failed:      cstring,
}

// Slot index of the function table a JNIEnv or a JavaVM points at.
jni_function :: proc(table_owner: rawptr, index: int) -> rawptr {
	return (cast(^[^]rawptr)table_owner)^[index]
}

// This thread's JNIEnv, attaching the thread when it is not; nil when the
// VM refuses.
jni_environment :: proc() -> rawptr {
	vm := GetAndroidApp().activity.vm
	attach := cast(Jni_Attach_Current_Thread)jni_function(vm, JNI_INVOKE_ATTACH_CURRENT_THREAD)
	environment: rawptr
	if attach(vm, &environment, nil) != JNI_OK {
		return nil
	}
	return environment
}

// Clears a pending exception and records the call as failed when one was
// thrown or the call gave no object.
jni_checked :: proc(calls: ^Jni_Calls, result: rawptr, what: cstring, needs_result := true) -> rawptr {
	check := cast(Jni_Exception_Check)jni_function(calls.environment, JNI_EXCEPTION_CHECK)
	if check(calls.environment) != 0 {
		clear_exception := cast(Jni_Exception_Clear)jni_function(calls.environment, JNI_EXCEPTION_CLEAR)
		clear_exception(calls.environment)
		calls.failed = what
		return nil
	}
	if needs_result && result == nil {
		calls.failed = what
	}
	return result
}

jni_find_class :: proc(calls: ^Jni_Calls, name: cstring) -> rawptr {
	if calls.failed != nil {
		return nil
	}
	find_class := cast(Jni_Find_Class)jni_function(calls.environment, JNI_FIND_CLASS)
	return jni_checked(calls, find_class(calls.environment, name), name)
}

jni_method :: proc(calls: ^Jni_Calls, class: rawptr, name, signature: cstring, is_static := false) -> rawptr {
	if calls.failed != nil {
		return nil
	}
	index := is_static ? JNI_GET_STATIC_METHOD_ID : JNI_GET_METHOD_ID
	get_method := cast(Jni_Get_Method_Id)jni_function(calls.environment, index)
	return jni_checked(calls, get_method(calls.environment, class, name, signature), name)
}

jni_call_object :: proc(calls: ^Jni_Calls, object, method: rawptr, arguments: []Jni_Value, what: cstring, is_static := false) -> rawptr {
	if calls.failed != nil {
		return nil
	}
	index := is_static ? JNI_CALL_STATIC_OBJECT_METHOD_A : JNI_CALL_OBJECT_METHOD_A
	call := cast(Jni_Call_Object_Method)jni_function(calls.environment, index)
	return jni_checked(calls, call(calls.environment, object, method, raw_data(arguments)), what)
}

jni_call_boolean :: proc(calls: ^Jni_Calls, object, method: rawptr, what: cstring) -> bool {
	if calls.failed != nil {
		return false
	}
	call := cast(Jni_Call_Boolean_Method)jni_function(calls.environment, JNI_CALL_BOOLEAN_METHOD_A)
	result := call(calls.environment, object, method, nil)
	jni_checked(calls, nil, what, needs_result = false)
	return calls.failed == nil && result != 0
}

jni_call_void :: proc(calls: ^Jni_Calls, object, method: rawptr, arguments: []Jni_Value, what: cstring) {
	if calls.failed != nil {
		return
	}
	call := cast(Jni_Call_Void_Method)jni_function(calls.environment, JNI_CALL_VOID_METHOD_A)
	call(calls.environment, object, method, raw_data(arguments))
	jni_checked(calls, nil, what, needs_result = false)
}

jni_new_string :: proc(calls: ^Jni_Calls, text: cstring) -> rawptr {
	if calls.failed != nil {
		return nil
	}
	new_string := cast(Jni_New_String_Utf)jni_function(calls.environment, JNI_NEW_STRING_UTF)
	return jni_checked(calls, new_string(calls.environment, text), "NewStringUTF")
}

jni_new_global_reference :: proc(calls: ^Jni_Calls, object: rawptr) -> rawptr {
	if calls.failed != nil {
		return nil
	}
	new_reference := cast(Jni_New_Reference)jni_function(calls.environment, JNI_NEW_GLOBAL_REF)
	return jni_checked(calls, new_reference(calls.environment, object), "NewGlobalRef")
}

// Deleting nil is allowed by JNI, so a run that failed half way cleans up
// the same way.
jni_delete_reference :: proc(environment, object: rawptr, index := JNI_DELETE_LOCAL_REF) {
	delete_reference := cast(Jni_Delete_Reference)jni_function(environment, index)
	delete_reference(environment, object)
}

// activity.getSystemService("vibrator"), a local reference.
jni_vibrator_service :: proc(calls: ^Jni_Calls) -> rawptr {
	context_class := jni_find_class(calls, "android/content/Context")
	get_system_service := jni_method(calls, context_class, "getSystemService", "(Ljava/lang/String;)Ljava/lang/Object;")
	name := jni_new_string(calls, "vibrator")
	arguments := [1]Jni_Value{{object = name}}
	service := jni_call_object(calls, GetAndroidApp().activity.clazz, get_system_service, arguments[:], "getSystemService")
	jni_delete_reference(calls.environment, name)
	jni_delete_reference(calls.environment, context_class)
	return service
}

// The vibrator's method ids and whether it vibrates at all.
find_vibrator_methods :: proc(calls: ^Jni_Calls, state: ^Vibrator_State, service: rawptr) -> (has_vibrator: bool) {
	vibrator_class := jni_find_class(calls, "android/os/Vibrator")
	has_vibrator_method := jni_method(calls, vibrator_class, "hasVibrator", "()Z")
	amplitude_control_method := jni_method(calls, vibrator_class, "hasAmplitudeControl", "()Z")
	state.vibrate = jni_method(calls, vibrator_class, "vibrate", "(Landroid/os/VibrationEffect;)V")
	state.cancel = jni_method(calls, vibrator_class, "cancel", "()V")
	jni_delete_reference(calls.environment, vibrator_class)
	has_vibrator = jni_call_boolean(calls, service, has_vibrator_method, "hasVibrator")
	state.amplitude_control = jni_call_boolean(calls, service, amplitude_control_method, "hasAmplitudeControl")
	return has_vibrator
}

find_vibration_effect :: proc(calls: ^Jni_Calls, state: ^Vibrator_State) {
	effect_class := jni_find_class(calls, "android/os/VibrationEffect")
	state.create_one_shot = jni_method(calls, effect_class, "createOneShot", "(JI)Landroid/os/VibrationEffect;", is_static = true)
	state.effect_class = jni_new_global_reference(calls, effect_class)
	jni_delete_reference(calls.environment, effect_class)
}

// Looks the vibrator up once and logs what it found.
start_vibrator :: proc() -> Vibrator_State {
	environment := jni_environment()
	if environment == nil {
		log_printf("haptics: no vibrator (the game thread could not attach to the Java VM)")
		return {}
	}
	calls := Jni_Calls {
		environment = environment,
	}
	state: Vibrator_State
	service := jni_vibrator_service(&calls)
	has_vibrator := find_vibrator_methods(&calls, &state, service)
	find_vibration_effect(&calls, &state)
	state.vibrator = jni_new_global_reference(&calls, service)
	jni_delete_reference(environment, service)
	if calls.failed != nil {
		log_printf("haptics: no vibrator (%s failed)", calls.failed)
		release_vibrator_references(environment, state)
		return {}
	}
	log_printf("haptics: vibrator %s, amplitude control %s", has_vibrator ? "found" : "absent", state.amplitude_control ? "yes" : "no")
	state.available = has_vibrator
	return state
}

release_vibrator_references :: proc(environment: rawptr, state: Vibrator_State) {
	jni_delete_reference(environment, state.vibrator, JNI_DELETE_GLOBAL_REF)
	jni_delete_reference(environment, state.effect_class, JNI_DELETE_GLOBAL_REF)
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
	calls := Jni_Calls {
		environment = jni_environment(),
	}
	if calls.environment == nil {
		calls.failed = "AttachCurrentThread"
	} else if amplitude == 0 {
		jni_call_void(&calls, state.vibrator, state.cancel, nil, "cancel")
	} else {
		play_vibration(&calls, state^, state.amplitude_control ? amplitude : VIBRATION_DEFAULT_AMPLITUDE)
	}
	state.vibrating = amplitude > 0
	if calls.failed != nil {
		log_printf("haptics: %s failed, the vibrator is off", calls.failed)
		state.available = false
	}
}

play_vibration :: proc(calls: ^Jni_Calls, state: Vibrator_State, amplitude: i32) {
	one_shot_arguments := [2]Jni_Value{{long = HAPTIC_RUMBLE_MILLISECONDS}, {integer = amplitude}}
	effect := jni_call_object(calls, state.effect_class, state.create_one_shot, one_shot_arguments[:], "createOneShot", is_static = true)
	vibrate_arguments := [1]Jni_Value{{object = effect}}
	jni_call_void(calls, state.vibrator, state.vibrate, vibrate_arguments[:], "vibrate")
	jni_delete_reference(calls.environment, effect)
}

// At the end of run_game: cancels a running vibration, frees the global
// references and detaches the game thread, which must not end attached
// (the activity can end while the process lives, main_android.odin).
stop_vibrator :: proc(state: ^Vibrator_State) {
	apply_vibrator_haptics(state, {})
	environment := jni_environment()
	if environment != nil {
		release_vibrator_references(environment, state^)
	}
	state^ = {}
	vm := GetAndroidApp().activity.vm
	detach := cast(Jni_Detach_Current_Thread)jni_function(vm, JNI_INVOKE_DETACH_CURRENT_THREAD)
	detach(vm)
}
