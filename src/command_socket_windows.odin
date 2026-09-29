#+build windows
package game

// The Windows side of the command socket (work item 0102): no Unix domain
// sockets, so the server never opens. The procedures the frame loop calls
// exist with the POSIX side's names and signatures and do nothing. The
// frame loop never calls open_command_server here, since
// COMMAND_SOCKET_SUPPORTED is false, so developer mode logs no socket
// line. The stub still returns a problem for completeness. No
// posix package here: its import alone links the static C runtime
// (libucrt.lib), which clashes with raylib's release library.

// listening stays -1, lines stays empty; the fields the frame loop and
// take_command_line read.
Command_Server :: struct {
	listening:   int,
	path:        string,
	lines:       [dynamic]Queued_Command_Line,
	open_failed: bool,
	tick_client: u64,
}

COMMAND_SOCKET_SUPPORTED :: false

make_command_server :: proc() -> Command_Server {
	return Command_Server{listening = -1}
}

open_command_server :: proc(server: ^Command_Server, path: string) -> string {
	return "no command socket on Windows"
}

close_command_server :: proc(server: ^Command_Server) {}

destroy_command_server :: proc(server: ^Command_Server) {
	delete(server.lines)
}

poll_command_server :: proc(server: ^Command_Server) {}

send_command_response :: proc(server: ^Command_Server, serial: u64, text: string) {}

flush_command_server :: proc(server: ^Command_Server) {}
