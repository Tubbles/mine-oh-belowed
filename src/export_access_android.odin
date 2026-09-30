#+build linux:android
package game

// All files access for the data export (work item 0131, doc/build.md,
// Android app): the export directory is on shared storage (a Syncthing
// folder), which scoped storage keeps from the app unless the user grants
// MANAGE_EXTERNAL_STORAGE on the settings page. Through JNI as the
// vibrator (haptics_android.odin, whose helpers these use): attached
// first, every local reference deleted by hand.

ALL_FILES_ACCESS_SETTINGS_ACTION :: "android.settings.MANAGE_APP_ALL_FILES_ACCESS_PERMISSION"
// The list of every app's All files access, for a device without the
// per app page (startActivity throws ActivityNotFoundException there).
ALL_FILES_ACCESS_LIST_ACTION :: "android.settings.MANAGE_ALL_FILES_ACCESS_PERMISSION"

Jni_Call_Static_Boolean_Method :: #type proc "c" (environment, class, method: rawptr, arguments: [^]Jni_Value) -> u8
Jni_New_Object :: #type proc "c" (environment, class, method: rawptr, arguments: [^]Jni_Value) -> rawptr

jni_call_static_boolean :: proc(calls: ^Jni_Calls, class, method: rawptr, what: cstring) -> bool {
	if calls.failed != nil {
		return false
	}
	call := cast(Jni_Call_Static_Boolean_Method)jni_function(calls.environment, JNI_CALL_STATIC_BOOLEAN_METHOD_A)
	result := call(calls.environment, class, method, nil)
	jni_checked(calls, nil, what, needs_result = false)
	return calls.failed == nil && result != 0
}

jni_new_object :: proc(calls: ^Jni_Calls, class, constructor: rawptr, arguments: []Jni_Value, what: cstring) -> rawptr {
	if calls.failed != nil {
		return nil
	}
	new_object := cast(Jni_New_Object)jni_function(calls.environment, JNI_NEW_OBJECT_A)
	return jni_checked(calls, new_object(calls.environment, class, constructor, raw_data(arguments)), what)
}

// Environment.isExternalStorageManager(). A failed call (the method is
// missing before Android 11, API 30) counts as granted, so the export
// tries and a refused write is toasted with its path.
all_files_access_granted :: proc() -> bool {
	environment := jni_environment()
	if environment == nil {
		log_printf("export: cannot ask for All files access (the game thread could not attach to the Java VM)")
		return true
	}
	calls := Jni_Calls {
		environment = environment,
	}
	environment_class := jni_find_class(&calls, "android/os/Environment")
	is_manager := jni_method(&calls, environment_class, "isExternalStorageManager", "()Z", is_static = true)
	granted := jni_call_static_boolean(&calls, environment_class, is_manager, "isExternalStorageManager")
	jni_delete_reference(environment, environment_class)
	if calls.failed != nil {
		log_printf("export: %s failed, exporting without the All files access check", calls.failed)
		return true
	}
	return granted
}

// The app's page of All files access in the system settings:
// activity.startActivity(new Intent(ACTION, Uri.fromParts("package",
// activity.getPackageName(), null))); when that fails, the list of every
// app's access (new Intent(LIST_ACTION), no URI).
open_all_files_access_settings :: proc() {
	environment := jni_environment()
	if environment == nil {
		log_printf("export: cannot open the All files access settings (the game thread could not attach to the Java VM)")
		return
	}
	calls := Jni_Calls {
		environment = environment,
	}
	activity := GetAndroidApp().activity.clazz
	context_class := jni_find_class(&calls, "android/content/Context")
	start_activity := jni_method(&calls, context_class, "startActivity", "(Landroid/content/Intent;)V")
	uri := jni_package_uri(&calls, context_class, activity)
	start_settings_activity(&calls, activity, start_activity, ALL_FILES_ACCESS_SETTINGS_ACTION, uri)
	jni_delete_reference(environment, uri)
	if calls.failed != nil && start_activity != nil {
		log_printf("export: %s failed, opening the list of All files access instead", calls.failed)
		calls.failed = nil
		start_settings_activity(&calls, activity, start_activity, ALL_FILES_ACCESS_LIST_ACTION, nil)
	}
	jni_delete_reference(environment, context_class)
	if calls.failed != nil {
		log_printf("export: %s failed, the All files access settings did not open", calls.failed)
		return
	}
	log_printf("export: opened the All files access settings")
}

// Uri.fromParts("package", activity.getPackageName(), null), a local
// reference.
jni_package_uri :: proc(calls: ^Jni_Calls, context_class, activity: rawptr) -> rawptr {
	get_package_name := jni_method(calls, context_class, "getPackageName", "()Ljava/lang/String;")
	package_name := jni_call_object(calls, activity, get_package_name, nil, "getPackageName")
	uri_class := jni_find_class(calls, "android/net/Uri")
	from_parts := jni_method(calls, uri_class, "fromParts", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Landroid/net/Uri;", is_static = true)
	scheme := jni_new_string(calls, "package")
	arguments := [3]Jni_Value{{object = scheme}, {object = package_name}, {object = nil}}
	uri := jni_call_object(calls, uri_class, from_parts, arguments[:], "Uri.fromParts", is_static = true)
	jni_delete_reference(calls.environment, scheme)
	jni_delete_reference(calls.environment, uri_class)
	jni_delete_reference(calls.environment, package_name)
	return uri
}

// activity.startActivity(new Intent(action, uri)), or new Intent(action)
// without a uri.
start_settings_activity :: proc(calls: ^Jni_Calls, activity, start_activity: rawptr, action: cstring, uri: rawptr) {
	intent := jni_settings_intent(calls, action, uri)
	arguments := [1]Jni_Value{{object = intent}}
	jni_call_void(calls, activity, start_activity, arguments[:], "startActivity")
	jni_delete_reference(calls.environment, intent)
}

// new Intent(action, uri), or new Intent(action) for a nil uri, a local
// reference.
jni_settings_intent :: proc(calls: ^Jni_Calls, action: cstring, uri: rawptr) -> rawptr {
	intent_class := jni_find_class(calls, "android/content/Intent")
	signature: cstring = uri == nil ? "(Ljava/lang/String;)V" : "(Ljava/lang/String;Landroid/net/Uri;)V"
	constructor := jni_method(calls, intent_class, "<init>", signature)
	action_string := jni_new_string(calls, action)
	arguments := [2]Jni_Value{{object = action_string}, {object = uri}}
	intent := jni_new_object(calls, intent_class, constructor, arguments[:], "new Intent")
	jni_delete_reference(calls.environment, action_string)
	jni_delete_reference(calls.environment, intent_class)
	return intent
}
