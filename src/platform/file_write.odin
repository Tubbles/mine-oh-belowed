package platform

import "core:fmt"
import "core:os"
import "core:strings"

// Writes the data beside the path first, then renames it over the path,
// making the directories it needs, so a failed write never leaves a cut
// off file (for the next start, or for Syncthing to spread). The file gets
// the default permissions, whatever its source had. The problem, or "".
// The files the game writes and reads back at start go through it (work
// item 0149): settings, touch layouts, texture edits, data edits, exports.
write_file_replacing :: proc(path: string, data: []byte) -> string {
	directory, _ := os.split_path(path)
	if error := make_directory_path(directory); error != nil {
		return fmt.tprintf("%v: %s", error, directory)
	}
	temporary := strings.concatenate({path, ".tmp"}, context.temp_allocator)
	if error := os.write_entire_file(temporary, data); error != nil {
		os.remove(temporary)
		return fmt.tprintf("%v: %s", error, temporary)
	}
	if error := os.rename(temporary, path); error != nil {
		os.remove(temporary)
		return fmt.tprintf("%v: %s", error, path)
	}
	return ""
}

// Renames the file to its path with the suffix appended, over an older
// file of that name: the file is kept for a look, never deleted. Returns
// the new path (in the temp allocator) and the problem, or "".
rename_file_aside :: proc(path, suffix: string) -> (aside: string, problem: string) {
	aside = strings.concatenate({path, suffix}, context.temp_allocator)
	if error := os.rename(path, aside); error != nil {
		return aside, fmt.tprintf("%v: %s", error, aside)
	}
	return aside, ""
}
