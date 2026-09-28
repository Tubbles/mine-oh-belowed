package game

import "core:os"
import "core:strings"
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

// Imports that link the static C runtime (libucrt.lib) on Windows by their
// mere presence, which clashes with raylib's release library, built for
// the dynamic runtime (work item 0102, the first two CI runs). A `when`
// block does not help, since the import itself adds the library; only a
// build tag that keeps the file out of the Windows build does.
// Split so that a grep over src/ for the two import paths lists only the
// files that import them.
WINDOWS_STATIC_RUNTIME_IMPORTS :: [?]string{`"core:sys/` + `posix"`, `"core:c/` + `libc"`}
BUILD_TAG_OPERATING_SYSTEMS :: [?]string{"linux", "darwin", "freebsd", "openbsd", "netbsd", "haiku", "essence", "freestanding", "wasi", "js", "orca"}

import_line_names :: proc(line, package_name: string) -> bool {
	trimmed := strings.trim_space(line)
	return strings.has_prefix(trimmed, "import ") && strings.contains(trimmed, package_name)
}

imports_windows_static_runtime :: proc(source: string) -> bool {
	for line in strings.split_lines(source, context.temp_allocator) {
		for package_name in WINDOWS_STATIC_RUNTIME_IMPORTS {
			if import_line_names(line, package_name) {
				return true
			}
		}
	}
	return false
}

// A clause of space separated terms (all must hold) excludes Windows when
// it says !windows or names another operating system.
build_clause_excludes_windows :: proc(clause: string) -> bool {
	for term in strings.fields(clause, context.temp_allocator) {
		if term == "!windows" {
			return true
		}
		for system in BUILD_TAG_OPERATING_SYSTEMS {
			if term == system {
				return true
			}
		}
	}
	return false
}

// #+build lines hold comma separated clauses (any may hold); a file is
// out of the Windows build when one of its lines excludes Windows in
// every clause. Only the lines before `package` count.
build_tags_exclude_windows :: proc(source: string) -> bool {
	for line in strings.split_lines(source, context.temp_allocator) {
		trimmed := strings.trim_space(line)
		if strings.has_prefix(trimmed, "package ") {
			return false
		}
		if !strings.has_prefix(trimmed, "#+build ") {
			continue
		}
		excluded := true
		for clause in strings.split(trimmed[len("#+build "):], ",", context.temp_allocator) {
			excluded &&= build_clause_excludes_windows(clause)
		}
		if excluded {
			return true
		}
	}
	return false
}

@(test)
test_build_tags_exclude_windows :: proc(t: ^testing.T) {
	testing.expect(t, build_tags_exclude_windows("#+build !windows\npackage game\n"))
	testing.expect(t, build_tags_exclude_windows("#+build linux, darwin\npackage game\n"))
	testing.expect(t, !build_tags_exclude_windows("#+build linux, windows\npackage game\n"))
	testing.expect(t, !build_tags_exclude_windows("#+build windows\npackage game\n"))
	testing.expect(t, !build_tags_exclude_windows("package game\n#+build !windows\n"))
	testing.expect(t, imports_windows_static_runtime("package game\n\nimport \"core:sys/" + "posix\"\n"))
	testing.expect(t, !imports_windows_static_runtime("package game\n// not through core:c/" + "libc\n"))
}

// Every game source file that imports the posix or the libc package of
// core must be kept out of the Windows build by its build tag.
@(test)
test_static_runtime_imports_stay_out_of_windows :: proc(t: ^testing.T) {
	directory := #directory
	entries, error := os.read_all_directory_by_path(directory, context.temp_allocator)
	testing.expect(t, error == nil, "cannot read the source directory")
	checked := 0
	for entry in entries {
		if entry.type != .Regular || !strings.has_suffix(entry.name, ".odin") {
			continue
		}
		path, _ := os.join_path({directory, entry.name}, context.temp_allocator)
		data, read_error := os.read_entire_file(path, context.temp_allocator)
		testing.expect(t, read_error == nil, path)
		checked += 1
		source := string(data)
		if imports_windows_static_runtime(source) {
			testing.expectf(t, build_tags_exclude_windows(source), "%s imports the posix or libc package of core without a #+build tag that excludes windows", entry.name)
		}
	}
	testing.expect(t, checked > 0, "no source files found")
}
