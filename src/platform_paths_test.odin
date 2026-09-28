package game

import "core:testing"

// The Windows mapping through the same helpers the game calls, with Unix
// style absolute paths standing in for the Windows ones so it runs here.
@(test)
test_windows_platform_directories :: proc(t: ^testing.T) {
	directories := windows_platform_directories("/roaming", "/local")
	testing.expect_value(t, directories.config_home, "/roaming")
	testing.expect_value(t, directories.data_home, "/roaming")
	testing.expect_value(t, directories.state_home, "/local")
	testing.expect_value(t, directories.config_dirs, "")
	testing.expect_value(t, directories.runtime_directory, "")
	testing.expect_value(t, directories.home, "")

	log_directory, log_ok := log_directory_from_environment(directories.state_home, directories.home, context.temp_allocator)
	testing.expect(t, log_ok)
	testing.expect_value(t, log_directory, "/local/mine-oh-belowed")
	saves, saves_ok := saves_directory_from_environment("", directories.data_home, directories.home, context.temp_allocator)
	testing.expect(t, saves_ok)
	testing.expect_value(t, saves, "/roaming/mine-oh-belowed/saves")
	environment := Configuration_Environment{config_home = directories.config_home, config_dirs = directories.config_dirs, home = directories.home}
	configuration_directory, configuration_ok := user_configuration_directory(environment)
	testing.expect(t, configuration_ok)
	testing.expect_value(t, configuration_directory, "/roaming/mine-oh-belowed")
}

// Without the variables there is no directory, never a fallback under a
// home.
@(test)
test_windows_platform_directories_missing :: proc(t: ^testing.T) {
	directories := windows_platform_directories("", "")
	_, log_ok := log_directory_from_environment(directories.state_home, directories.home, context.temp_allocator)
	testing.expect(t, !log_ok)
	_, saves_ok := saves_directory_from_environment("", directories.data_home, directories.home, context.temp_allocator)
	testing.expect(t, !saves_ok)
}
