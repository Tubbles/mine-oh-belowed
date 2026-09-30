package game

import "core:os"
import "core:strings"
import "platform"

// The command socket (work item 0053, doc/commands.md): a Unix domain
// stream socket the game listens on while developer mode is on, at
// $XDG_RUNTIME_DIR/mine-oh-belowed/command.sock, or under
// $XDG_STATE_HOME (or ~/.local/state) without a runtime directory. The
// directory is made with mode 0700, so only the user reaches it. The
// frame loop polls the socket once per frame without blocking: it accepts
// clients, reads what they sent and splits it into lines, which queue in
// arrival order. Several clients may connect, one after the other or at
// once; each may send several lines and gets one response per line, in
// order. The loop executes the lines between ticks (loop.odin), so the
// simulation never reads the socket.
//
// This file holds what both systems share: the paths, the queued line and
// the command log. The socket itself is in command_socket_posix.odin; on
// Windows (work item 0102) command_socket_windows.odin gives the same
// procedures as stubs and the server never opens. They are separate
// files with build tags, not `when` blocks, because the posix package links
// the static C runtime on Windows by its import alone.

COMMAND_SOCKET_FILE_NAME :: "command.sock"

Queued_Command_Line :: struct {
	client: u64,
	line:   string,
}

// The runtime directory when it is absolute, else the state directory
// (logging.odin). In the given allocator.
command_socket_directory_from_environment :: proc(runtime_directory, state_home, home: string, allocator := context.allocator) -> (directory: string, ok: bool) {
	if runtime_directory != "" && os.is_absolute_path(runtime_directory) {
		joined, error := os.join_path({runtime_directory, platform.GAME_DIRECTORY_NAME}, allocator)
		return joined, error == nil
	}
	return platform.log_directory_from_environment(state_home, home, allocator)
}

command_socket_path_from_environment :: proc(runtime_directory, state_home, home: string, allocator := context.allocator) -> (path: string, ok: bool) {
	directory := command_socket_directory_from_environment(runtime_directory, state_home, home, context.temp_allocator) or_return
	joined, error := os.join_path({directory, COMMAND_SOCKET_FILE_NAME}, allocator)
	return joined, error == nil
}

// $XDG_STATE_HOME/mine-oh-belowed/screenshots. In the given allocator.
screenshot_directory_from_environment :: proc(state_home, home: string, allocator := context.allocator) -> (directory: string, ok: bool) {
	state_directory := platform.log_directory_from_environment(state_home, home, context.temp_allocator) or_return
	joined, error := os.join_path({state_directory, SCREENSHOT_DIRECTORY_NAME}, allocator)
	return joined, error == nil
}

// The oldest queued line; the caller deletes it.
take_command_line :: proc(server: ^Command_Server) -> (queued: Queued_Command_Line, ok: bool) {
	if len(server.lines) == 0 {
		return {}, false
	}
	queued = server.lines[0]
	ordered_remove(&server.lines, 0)
	return queued, true
}

// Every line and response line into the log.
log_command_exchange :: proc(line, response: string) {
	platform.log_printf("command: %s", line)
	for response_line in strings.split_lines(strings.trim_right(response, "\n"), context.temp_allocator) {
		platform.log_printf("command: -> %s", response_line)
	}
}
