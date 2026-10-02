package platform

import "base:runtime"
import "core:fmt"
import "core:net"
import "core:strings"
import "core:sync"
import "core:thread"

// The network transport of a lockstep session (work item 0177): TCP
// through core:net on every target (Linux and Android through the
// system calls, Windows through Winsock), messages framed by a little
// endian u32 length, sockets non blocking, polled once per frame. A host
// listens and accepts, a client connects. The messages are bytes here; the
// game encodes them (session_network.odin). No UDP.
//
// Addresses are host:port; the port may be left out for the default. A
// host name needs the system's resolver: on the phone, which has no
// /etc/resolv.conf for core:net to read, give an IP address.

DEFAULT_NETWORK_PORT :: 47_317
// A length prefix above this closes the connection: a malformed or
// foreign stream must not make the game allocate gigabytes. A join's save
// of a large world stays far below it.
MAXIMUM_NETWORK_MESSAGE_SIZE :: 512 * 1024 * 1024
NETWORK_RECEIVE_CHUNK_SIZE :: 64 * 1024
NETWORK_LENGTH_SIZE :: 4

Network_Listener :: struct {
	socket: net.TCP_Socket,
	open:   bool,
	port:   int,
}

// address is the peer as text (owned). problem says why a closed
// connection closed.
Network_Connection :: struct {
	socket:   net.TCP_Socket,
	open:     bool,
	address:  string,
	received: [dynamic]byte,
	unsent:   [dynamic]byte,
	problem:  string,
	// Every byte received so far, for the keepalive (a peer is alive while
	// bytes arrive, even inside a long message).
	received_total: int,
}

// The address a listener binds: every interface for the server, the
// loopback for the tests.
Listen_Address :: enum u8 {
	Any,
	Loopback,
}

listen_on_port :: proc(port: int, address := Listen_Address.Any) -> (listener: Network_Listener, problem: string) {
	bound_address: net.Address = address == .Loopback ? net.IP4_Loopback : net.IP4_Any
	socket, error := net.listen_tcp(net.Endpoint{address = bound_address, port = port})
	if error != nil {
		return {}, fmt.tprintf("cannot listen on port %d: %v", port, error)
	}
	if blocking_error := net.set_blocking(socket, false); blocking_error != nil {
		net.close(socket)
		return {}, fmt.tprintf("cannot make port %d non blocking: %v", port, blocking_error)
	}
	// Port 0 lets the system choose (the tests).
	bound, bound_error := net.bound_endpoint(socket)
	if bound_error != nil {
		net.close(socket)
		return {}, fmt.tprintf("cannot read the port of the listener: %v", bound_error)
	}
	return Network_Listener{socket = socket, open = true, port = bound.port}, ""
}

close_listener :: proc(listener: ^Network_Listener) {
	if listener.open {
		net.close(listener.socket)
	}
	listener^ = {}
}

// One waiting connection, or accepted false when none waits.
accept_connection :: proc(listener: ^Network_Listener) -> (connection: Network_Connection, accepted: bool) {
	if !listener.open {
		return {}, false
	}
	socket, source, error := net.accept_tcp(listener.socket)
	if error != nil {
		return {}, false
	}
	if net.set_blocking(socket, false) != nil {
		net.close(socket)
		return {}, false
	}
	return Network_Connection{socket = socket, open = true, address = strings.clone(net.endpoint_to_string(source, context.temp_allocator))}, true
}

// The endpoint of host:port, host:default port, or a host name through
// the resolver.
network_endpoint :: proc(address: string) -> (endpoint: net.Endpoint, problem: string) {
	text := address
	if !strings.contains(text, ":") {
		text = fmt.tprintf("%s:%d", address, DEFAULT_NETWORK_PORT)
	} else if !valid_port_text(text[strings.last_index_byte(text, ':') + 1:]) {
		return {}, fmt.tprintf("invalid port in %s (expected 1 to 65535)", address)
	}
	if parsed, ok := net.parse_endpoint(text); ok && parsed.port != 0 {
		return parsed, ""
	}
	resolved, error := net.resolve_ip4(text)
	if error != nil {
		return {}, fmt.tprintf("cannot resolve %s: %v", address, error)
	}
	return resolved, ""
}

// Digits only and 1 to 65535, checked before any conversion, since a
// parsed number could wrap.
valid_port_text :: proc(text: string) -> bool {
	if len(text) == 0 || len(text) > 5 {
		return false
	}
	port := 0
	for character in transmute([]byte)text {
		if character < '0' || character > '9' {
			return false
		}
		port = port * 10 + int(character - '0')
	}
	return port >= 1 && port <= 65_535
}

// A connection being made on a thread of its own (net.dial_tcp blocks up
// to the system's connect timeout, which would freeze the window). The
// frame polls take_dial; a dial given up (abandon_dial) finishes on its
// thread, which closes its socket and frees it.
Network_Dial :: struct {
	mutex:      sync.Mutex,
	address:    string,
	done:       bool,
	abandoned:  bool,
	connection: Network_Connection,
	problem:    string,
}

start_dial :: proc(address: string) -> ^Network_Dial {
	dial := new(Network_Dial)
	dial.address = strings.clone(address)
	// The caller's context, so the dial's allocations are the caller's
	// (run_dial gives the thread its own temp allocator).
	thread.create_and_start_with_poly_data(dial, run_dial, init_context = context, self_cleanup = true)
	return dial
}

run_dial :: proc(dial: ^Network_Dial) {
	context.temp_allocator = runtime.Allocator{procedure = runtime.default_temp_allocator_proc, data = &runtime.global_default_temp_allocator_data}
	connection, problem := connect_to(dial.address)
	sync.mutex_lock(&dial.mutex)
	abandoned := dial.abandoned
	dial.connection, dial.problem, dial.done = connection, strings.clone(problem), true
	sync.mutex_unlock(&dial.mutex)
	if abandoned {
		free_dial(dial)
	}
}

free_dial :: proc(dial: ^Network_Dial) {
	destroy_connection(&dial.connection)
	delete(dial.problem)
	delete(dial.address)
	free(dial)
}

// done false while the dial runs. Once done the connection (or the
// problem, owned by the caller) is taken and the dial is freed.
take_dial :: proc(dial: ^Network_Dial) -> (connection: Network_Connection, problem: string, done: bool) {
	sync.mutex_lock(&dial.mutex)
	done = dial.done
	sync.mutex_unlock(&dial.mutex)
	if !done {
		return {}, "", false
	}
	connection, problem = dial.connection, dial.problem
	dial.connection, dial.problem = {}, ""
	free_dial(dial)
	return connection, problem, true
}

// The caller stops waiting; the dial's thread frees it when it ends.
abandon_dial :: proc(dial: ^Network_Dial) {
	sync.mutex_lock(&dial.mutex)
	done := dial.done
	dial.abandoned = true
	sync.mutex_unlock(&dial.mutex)
	if done {
		free_dial(dial)
	}
}

// Connects blocking, then the socket goes non blocking. The game calls it
// on a dial's thread (start_dial); the tests call it directly.
connect_to :: proc(address: string) -> (connection: Network_Connection, problem: string) {
	endpoint: net.Endpoint
	if endpoint, problem = network_endpoint(address); problem != "" {
		return {}, problem
	}
	socket, error := net.dial_tcp(endpoint)
	if error != nil {
		return {}, fmt.tprintf("cannot connect to %s: %v", address, error)
	}
	if net.set_blocking(socket, false) != nil {
		net.close(socket)
		return {}, fmt.tprintf("cannot make the connection to %s non blocking", address)
	}
	return Network_Connection{socket = socket, open = true, address = strings.clone(net.endpoint_to_string(endpoint, context.temp_allocator))}, ""
}

close_connection :: proc(connection: ^Network_Connection, problem: string = "") {
	if connection.open {
		net.close(connection.socket)
		connection.open = false
		connection.problem = problem
	}
}

destroy_connection :: proc(connection: ^Network_Connection) {
	close_connection(connection)
	delete(connection.address)
	delete(connection.received)
	delete(connection.unsent)
	connection^ = {}
}

// The length prefix and the payload, sent as far as the socket takes
// them; the rest goes on the next flush.
send_message :: proc(connection: ^Network_Connection, payload: []byte) {
	if !connection.open {
		return
	}
	length := u32(len(payload))
	for index in 0 ..< NETWORK_LENGTH_SIZE {
		append(&connection.unsent, byte(length >> (8 * uint(index))))
	}
	append(&connection.unsent, ..payload)
	flush_connection(connection)
}

flush_connection :: proc(connection: ^Network_Connection) {
	if !connection.open || len(connection.unsent) == 0 {
		return
	}
	written, error := net.send_tcp(connection.socket, connection.unsent[:])
	remove_range(&connection.unsent, 0, written)
	if error != .None && error != .Would_Block && error != .Interrupted {
		close_connection(connection, fmt.tprintf("send failed: %v", error))
	}
}

// Reads what has arrived without blocking. A peer that closed, or a read
// error, closes the connection.
poll_connection :: proc(connection: ^Network_Connection) {
	flush_connection(connection)
	buffer: [NETWORK_RECEIVE_CHUNK_SIZE]byte
	for connection.open {
		count, error := net.recv_tcp(connection.socket, buffer[:])
		switch {
		case error == .Would_Block || error == .Interrupted:
			return
		case error != .None:
			close_connection(connection, fmt.tprintf("receive failed: %v", error))
		case count == 0:
			close_connection(connection, "closed by the peer")
		case:
			append(&connection.received, ..buffer[:count])
			connection.received_total += count
		}
	}
}

// The next whole message, in the allocator, or ok false. A length above
// MAXIMUM_NETWORK_MESSAGE_SIZE closes the connection.
take_message :: proc(connection: ^Network_Connection, allocator := context.allocator) -> (payload: []byte, ok: bool) {
	if len(connection.received) < NETWORK_LENGTH_SIZE {
		return nil, false
	}
	length := 0
	for index in 0 ..< NETWORK_LENGTH_SIZE {
		length |= int(connection.received[index]) << (8 * uint(index))
	}
	if length > MAXIMUM_NETWORK_MESSAGE_SIZE {
		close_connection(connection, fmt.tprintf("a message of %d bytes is over the limit", length))
		clear(&connection.received)
		return nil, false
	}
	if len(connection.received) < NETWORK_LENGTH_SIZE + length {
		return nil, false
	}
	payload = make([]byte, length, allocator)
	copy(payload, connection.received[NETWORK_LENGTH_SIZE:][:length])
	remove_range(&connection.received, 0, NETWORK_LENGTH_SIZE + length)
	return payload, true
}
