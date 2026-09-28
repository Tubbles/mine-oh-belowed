#+build windows
package game

import "core:testing"

// No command socket on Windows (work item 0102): the stub refuses to open
// and the server stays closed.
@(test)
test_command_socket_is_off_on_windows :: proc(t: ^testing.T) {
	server := make_command_server()
	defer destroy_command_server(&server)
	testing.expect_value(t, open_command_server(&server, "unused"), "no command socket on Windows")
	testing.expect_value(t, server.listening, -1)
}
