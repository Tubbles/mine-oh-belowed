package platform

import "core:os"

// The base directories the path helpers take (logging.odin,
// configuration.odin, save_world.odin, command_socket.odin,
// texture_generate.odin), read from the environment in one place.
//
// Linux: the XDG base directory variables and $HOME, each helper applying
// the XDG rules (a relative value is ignored, $HOME/.config,
// $HOME/.local/state and $HOME/.local/share stand in for unset ones).
//
// Windows (work item 0102, run under Wine through GameNative, which sets
// no XDG variable and no HOME): %APPDATA% stands in for the config home
// and the data home, so configuration and saves roam, and %LOCALAPPDATA%
// for the state home (screenshots, texture edits; the log sits beside the
// executable instead, work item 0103). The helpers append mine-oh-belowed
// to both. There is no runtime directory, no system configuration
// directory and no home, so a missing variable means no directory rather
// than a Unix style fallback, and a leading ~/ in a configured path stays
// as written.
//
// Android (work item 0114, no environment at all, doc/android.md, Files
// on the phone): the activity's external files folder
// (Android/data/<package>/files, which a USB connection and file managers
// reach) holds config, share and state in place of the three XDG homes,
// the internal data folder when there is no external one. No runtime
// directory and no home.
Platform_Directories :: struct {
	config_home:       string,
	config_dirs:       string,
	data_home:         string,
	state_home:        string,
	runtime_directory: string,
	home:              string,
}

when ODIN_OS == .Windows {
	// For the problem lines when a directory cannot be found.
	CONFIG_HOME_VARIABLES :: "APPDATA"
	DATA_HOME_VARIABLES :: "APPDATA"
	STATE_HOME_VARIABLES :: "LOCALAPPDATA"
} else when ODIN_PLATFORM_SUBTARGET == .Android {
	CONFIG_HOME_VARIABLES :: "the app's files folder, which Android did not report"
	DATA_HOME_VARIABLES :: "the app's files folder, which Android did not report"
	STATE_HOME_VARIABLES :: "the app's files folder, which Android did not report"
} else {
	CONFIG_HOME_VARIABLES :: "XDG_CONFIG_HOME or HOME"
	DATA_HOME_VARIABLES :: "XDG_DATA_HOME or HOME"
	STATE_HOME_VARIABLES :: "XDG_STATE_HOME or HOME"
}

NO_STATE_DIRECTORY_PROBLEM :: "no state directory (set " + STATE_HOME_VARIABLES + ")"

// In the given allocator.
platform_directories :: proc(allocator := context.allocator) -> Platform_Directories {
	when ODIN_OS == .Windows {
		return windows_platform_directories(os.get_env("APPDATA", allocator), os.get_env("LOCALAPPDATA", allocator))
	} else when ODIN_PLATFORM_SUBTARGET == .Android {
		internal, external := android_data_paths()
		return android_platform_directories(internal, external, allocator)
	} else {
		return Platform_Directories {
			config_home = os.get_env("XDG_CONFIG_HOME", allocator),
			config_dirs = os.get_env("XDG_CONFIG_DIRS", allocator),
			data_home = os.get_env("XDG_DATA_HOME", allocator),
			state_home = os.get_env("XDG_STATE_HOME", allocator),
			runtime_directory = os.get_env("XDG_RUNTIME_DIR", allocator),
			home = os.get_env("HOME", allocator),
		}
	}
}

// Pure, so the Windows mapping is tested on any host.
windows_platform_directories :: proc(application_data, local_application_data: string) -> Platform_Directories {
	return Platform_Directories{config_home = application_data, data_home = application_data, state_home = local_application_data}
}

// Pure, so the Android mapping is tested on any host. In the given
// allocator.
android_platform_directories :: proc(internal, external: string, allocator := context.allocator) -> Platform_Directories {
	base := external if external != "" else internal
	if base == "" {
		return {}
	}
	config_home, _ := os.join_path({base, "config"}, allocator)
	data_home, _ := os.join_path({base, "share"}, allocator)
	state_home, _ := os.join_path({base, "state"}, allocator)
	return Platform_Directories{config_home = config_home, data_home = data_home, state_home = state_home}
}

// The elements joined with the separator, in the temp allocator.
join_path :: proc(elements: ..string) -> string {
	joined, _ := os.join_path(elements, context.temp_allocator)
	return joined
}

// mkdir -p that never touches a directory above the first missing one
// (work item 0117). core:os's make_directory_all opens / to walk an
// absolute path, and Android's SELinux policy refuses an app that read
// (Permission_Denied on the phone, 2026-09-30), while a plain mkdir below
// the app's folder is allowed. So this tries the directory itself, makes
// the parent the same way when that is missing, and tries again. An
// existing directory is success. On Windows the same errors map to
// .Exist and .Not_Exist, so the same code serves there.
make_directory_path :: proc(path: string, permissions := os.Permissions_Default_Directory) -> os.Error {
	directory := trim_trailing_separators(path)
	error := os.make_directory(directory, permissions)
	if error == .Not_Exist {
		parent, _ := os.split_path(directory)
		if parent == "" || parent == directory {
			return error
		}
		make_directory_path(parent, permissions) or_return
		error = os.make_directory(directory, permissions)
	}
	if error == .Exist {
		return nil
	}
	return error
}

// Keeps a lone separator (the root).
trim_trailing_separators :: proc(path: string) -> string {
	end := len(path)
	for end > 1 && os.is_path_separator(path[end - 1]) {
		end -= 1
	}
	return path[:end]
}
