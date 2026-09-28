#+build windows
package game

// The Windows side of the command socket (work item 0102): no Unix domain
// sockets, so the server never opens. The procedures the frame loop calls
// exist with the POSIX side's names and signatures; open_command_server
// returns the problem the loop logs once, the rest do nothing. No
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
