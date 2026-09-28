package game

import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sys/posix"

// Used only on the Linux side of the when blocks below.
_ :: c
_ :: fmt

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
// simulation never reads the socket. Linux only: on Windows the server
// never opens (work item 0102).

COMMAND_SOCKET_FILE_NAME :: "command.sock"
// Bytes a client may send without a newline before it is dropped.
MAXIMUM_COMMAND_LINE_BYTES :: 64 * 1024
COMMAND_SOCKET_BACKLOG :: 8
COMMAND_READ_CHUNK_BYTES :: 4096

Command_Client :: struct {
	serial:     u64,
	descriptor: posix.FD,
	input:      [dynamic]byte,
	// Response bytes the socket did not take yet.
	output:     [dynamic]byte,
	// The client closed its end or failed: dropped once its queued lines
	// are answered and its output is out (or cannot go out).
	finished:   bool,
}

Queued_Command_Line :: struct {
	client: u64,
	line:   string,
}

// listening is -1 while closed. open_failed stops retrying every frame
// after a failure, until developer mode is switched off and on again.
Command_Server :: struct {
	listening:   posix.FD,
	path:        string,
	clients:     [dynamic]Command_Client,
	lines:       [dynamic]Queued_Command_Line,
	next_serial: u64,
	open_failed: bool,
	// The client waiting for the tick command's answer.
	tick_client: u64,
}

make_command_server :: proc() -> Command_Server {
	return Command_Server{listening = -1, next_serial = 1}
}

// The runtime directory when it is absolute, else the state directory
// (logging.odin). In the given allocator.
command_socket_directory_from_environment :: proc(runtime_directory, state_home, home: string, allocator := context.allocator) -> (directory: string, ok: bool) {
	if runtime_directory != "" && os.is_absolute_path(runtime_directory) {
		joined, error := os.join_path({runtime_directory, GAME_DIRECTORY_NAME}, allocator)
		return joined, error == nil
	}
	return log_directory_from_environment(state_home, home, allocator)
}

command_socket_path_from_environment :: proc(runtime_directory, state_home, home: string, allocator := context.allocator) -> (path: string, ok: bool) {
	directory := command_socket_directory_from_environment(runtime_directory, state_home, home, context.temp_allocator) or_return
	joined, error := os.join_path({directory, COMMAND_SOCKET_FILE_NAME}, allocator)
	return joined, error == nil
}

// $XDG_STATE_HOME/mine-oh-belowed/screenshots. In the given allocator.
screenshot_directory_from_environment :: proc(state_home, home: string, allocator := context.allocator) -> (directory: string, ok: bool) {
	state_directory := log_directory_from_environment(state_home, home, context.temp_allocator) or_return
	joined, error := os.join_path({state_directory, SCREENSHOT_DIRECTORY_NAME}, allocator)
	return joined, error == nil
}

// Opening.

when ODIN_OS == .Windows {
	// No Unix domain sockets on Windows (work item 0102): the server never
	// opens, the frame loop logs this once and polling stays a no op.
	open_command_server :: proc(server: ^Command_Server, path: string) -> string {
		return "no command socket on Windows"
	}
} else {
	unix_socket_address :: proc(path: string) -> (address: posix.sockaddr_un, ok: bool) {
		if len(path) >= len(address.sun_path) {
			return {}, false
		}
		address.sun_family = .UNIX
		for index in 0 ..< len(path) {
			address.sun_path[index] = c.char(path[index])
		}
		return address, true
	}

	set_non_blocking :: proc(descriptor: posix.FD) -> bool {
		flags := posix.fcntl(descriptor, .GETFL)
		if flags < 0 {
			return false
		}
		return posix.fcntl(descriptor, .SETFL, transmute(posix.O_Flags)flags + {.NONBLOCK}) >= 0
	}

	// A connection succeeds only while another game listens there.
	socket_is_live :: proc(address: ^posix.sockaddr_un) -> bool {
		probe := posix.socket(.UNIX, .STREAM)
		if probe == -1 {
			return false
		}
		defer posix.close(probe)
		return posix.connect(probe, (^posix.sockaddr)(address), size_of(posix.sockaddr_un)) == .OK
	}

	// Binds and listens at path in a directory made with mode 0700. A stale
	// socket file is removed first; one another game still listens on is left
	// alone and reported. Returns the problem, empty on success.
	open_command_server :: proc(server: ^Command_Server, path: string) -> string {
		directory, _ := os.split_path(path)
		if error := os.make_directory_all(directory, {.Read_User, .Write_User, .Execute_User}); error != nil && error != .Exist {
			return fmt.tprintf("cannot make %s: %v", directory, error)
		}
		posix.chmod(strings.clone_to_cstring(directory, context.temp_allocator), {.IRUSR, .IWUSR, .IXUSR})
		address, address_ok := unix_socket_address(path)
		if !address_ok {
			return fmt.tprintf("the socket path %s is too long", path)
		}
		if socket_is_live(&address) {
			return fmt.tprintf("another game listens on %s", path)
		}
		posix.unlink(strings.clone_to_cstring(path, context.temp_allocator))
		descriptor := posix.socket(.UNIX, .STREAM)
		if descriptor == -1 {
			return fmt.tprintf("socket: %v", posix.errno())
		}
		if posix.bind(descriptor, (^posix.sockaddr)(&address), size_of(address)) != .OK || posix.listen(descriptor, COMMAND_SOCKET_BACKLOG) != .OK || !set_non_blocking(descriptor) {
			problem := fmt.tprintf("cannot listen on %s: %v", path, posix.errno())
			posix.close(descriptor)
			return problem
		}
		server.listening = descriptor
		server.path = strings.clone(path)
		return ""
	}
}

// Closes every client, stops listening and removes the socket file.
close_command_server :: proc(server: ^Command_Server) {
	for client in server.clients {
		destroy_command_client(client)
	}
	clear(&server.clients)
	for queued in server.lines {
		delete(queued.line)
	}
	clear(&server.lines)
	when ODIN_OS != .Windows {
		if server.listening != -1 {
			posix.close(server.listening)
			posix.unlink(strings.clone_to_cstring(server.path, context.temp_allocator))
			server.listening = -1
		}
	}
	delete(server.path)
	server.path = ""
	server.tick_client = 0
}

destroy_command_server :: proc(server: ^Command_Server) {
	close_command_server(server)
	delete(server.clients)
	delete(server.lines)
}

destroy_command_client :: proc(client: Command_Client) {
	when ODIN_OS != .Windows {
		posix.close(client.descriptor)
	}
	delete(client.input)
	delete(client.output)
}

// Polling.

would_block :: proc(errno: posix.Errno) -> bool {
	return errno == .EAGAIN || errno == .EWOULDBLOCK || errno == .EINTR
}

accept_command_clients :: proc(server: ^Command_Server) {
	when ODIN_OS != .Windows {
		for {
			descriptor := posix.accept(server.listening, nil, nil)
			if descriptor == -1 {
				return
			}
			if !set_non_blocking(descriptor) {
				posix.close(descriptor)
				continue
			}
			append(&server.clients, Command_Client{serial = server.next_serial, descriptor = descriptor})
			server.next_serial += 1
		}
	}
}

// Reads what the client sent until the socket would block; end of file
// or an error finishes it.
read_command_client :: proc(client: ^Command_Client) {
	when ODIN_OS != .Windows {
		buffer: [COMMAND_READ_CHUNK_BYTES]byte
		for !client.finished {
			count := posix.recv(client.descriptor, &buffer[0], len(buffer), {})
			switch {
			case count > 0:
				append(&client.input, ..buffer[:count])
			case count == 0 || !would_block(posix.errno()):
				client.finished = true
			case:
				return
			}
		}
	}
}

// The complete lines of the client's input, queued as owned strings; a
// line without its newline stays for the next frame.
queue_client_lines :: proc(server: ^Command_Server, client: ^Command_Client) {
	start := 0
	for index in 0 ..< len(client.input) {
		if client.input[index] == '\n' {
			append(&server.lines, Queued_Command_Line{client = client.serial, line = strings.clone(string(client.input[start:index]))})
			start = index + 1
		}
	}
	remove_range(&client.input, 0, start)
	if len(client.input) > MAXIMUM_COMMAND_LINE_BYTES {
		queue_command_response(client, format_command_response(command_error("a line is longer than %d bytes", MAXIMUM_COMMAND_LINE_BYTES)))
		clear(&client.input)
		client.finished = true
	}
}

// Accepts, reads and queues the lines that arrived since the last frame.
poll_command_server :: proc(server: ^Command_Server) {
	if server.listening == -1 {
		return
	}
	accept_command_clients(server)
	for &client in server.clients {
		read_command_client(&client)
		queue_client_lines(server, &client)
	}
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

find_command_client :: proc(server: ^Command_Server, serial: u64) -> ^Command_Client {
	for &client in server.clients {
		if client.serial == serial {
			return &client
		}
	}
	return nil
}

queue_command_response :: proc(client: ^Command_Client, text: string) {
	append(&client.output, ..transmute([]byte)text)
}

// A client that went away meanwhile gets nothing.
send_command_response :: proc(server: ^Command_Server, serial: u64, text: string) {
	if client := find_command_client(server, serial); client != nil {
		queue_command_response(client, text)
	}
}

// Writes what the socket takes now; a broken connection finishes the
// client and drops its output.
flush_command_client :: proc(client: ^Command_Client) {
	when ODIN_OS != .Windows {
		for len(client.output) > 0 {
			count := posix.send(client.descriptor, &client.output[0], len(client.output), {.NOSIGNAL})
			if count < 0 {
				if !would_block(posix.errno()) {
					client.finished = true
					clear(&client.output)
				}
				return
			}
			remove_range(&client.output, 0, int(count))
		}
	}
}

client_has_queued_lines :: proc(server: ^Command_Server, serial: u64) -> bool {
	for queued in server.lines {
		if queued.client == serial {
			return true
		}
	}
	return serial == server.tick_client
}

// Sends the pending output and drops the finished clients that have
// nothing left to answer or send.
flush_command_server :: proc(server: ^Command_Server) {
	for index := len(server.clients) - 1; index >= 0; index -= 1 {
		client := &server.clients[index]
		flush_command_client(client)
		if client.finished && len(client.output) == 0 && !client_has_queued_lines(server, client.serial) {
			destroy_command_client(client^)
			ordered_remove(&server.clients, index)
		}
	}
}

// Every line and response line into the log.
log_command_exchange :: proc(line, response: string) {
	log_printf("command: %s", line)
	for response_line in strings.split_lines(strings.trim_right(response, "\n"), context.temp_allocator) {
		log_printf("command: -> %s", response_line)
	}
}
