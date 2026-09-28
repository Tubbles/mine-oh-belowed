#+build !windows
package game

import "core:os"
import "core:strings"
import "core:sys/posix"
import "core:testing"

// The POSIX command socket (command_socket_posix.odin). Excluded from the
// Windows build like the socket itself (work item 0102).

@(test)
test_unix_socket_address_refuses_long_paths :: proc(t: ^testing.T) {
	_, address_ok := unix_socket_address(strings.repeat("x", 200, context.temp_allocator))
	testing.expect(t, !address_ok)
}

// A real socket: bind a temporary path, connect, send help, read the
// answer up to its terminating line.
@(test)
test_command_socket_round_trip :: proc(t: ^testing.T) {
	directory, error := os.make_directory_temp("", "mine-oh-belowed-socket-test-*", context.temp_allocator)
	testing.expect(t, error == nil)
	defer os.remove_all(directory)
	path, _ := os.join_path({directory, "run", COMMAND_SOCKET_FILE_NAME}, context.temp_allocator)
	server := make_command_server()
	defer destroy_command_server(&server)
	testing.expect_value(t, open_command_server(&server, path), "")
	testing.expect(t, os.exists(path))

	address, _ := unix_socket_address(path)
	client := posix.socket(.UNIX, .STREAM)
	defer posix.close(client)
	testing.expect_value(t, posix.connect(client, (^posix.sockaddr)(&address), size_of(address)), posix.result.OK)
	message := "help\n# comment\n"
	testing.expect_value(t, int(posix.send(client, raw_data(message), len(message), {})), len(message))

	control: Command_Control
	command_context := Command_Context{control = &control}
	answered := 0
	for attempt := 0; attempt < 100 && answered < 2; attempt += 1 {
		poll_command_server(&server)
		for {
			queued := take_command_line(&server) or_break
			if response, empty := execute_command_line(command_context, queued.line); !empty {
				send_command_response(&server, queued.client, format_command_response(response))
			}
			answered += 1
			delete(queued.line)
		}
		flush_command_server(&server)
	}
	testing.expect_value(t, answered, 2)

	received := make([dynamic]byte, context.temp_allocator)
	buffer: [4096]byte
	for !strings.has_suffix(string(received[:]), "\n.\n") {
		count := posix.recv(client, &buffer[0], len(buffer), {})
		if count <= 0 {
			break
		}
		append(&received, ..buffer[:count])
	}
	text := string(received[:])
	testing.expect(t, strings.has_prefix(text, "ok commands\nhelp: "), text)
	testing.expect(t, strings.has_suffix(text, "\n.\n"), text)

	// A second server on the same path refuses while the first listens.
	second := make_command_server()
	defer destroy_command_server(&second)
	testing.expect(t, open_command_server(&second, path) != "")
	close_command_server(&server)
	testing.expect(t, !os.exists(path))
}
