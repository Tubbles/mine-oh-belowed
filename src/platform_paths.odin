package game

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
