package platform

import "core:fmt"
import "core:net"
import "core:strings"
import "core:unicode/utf8"

// The LAN discovery (work item 0188): UDP beside the TCP transport
// (network.odin). The title's Multiplayer screen broadcasts a query on
// DISCOVERY_PORT once a second; every hosting game answers the query's
// sender with one datagram naming the world, the host machine, its
// players, its TCP port and its build. Nothing else crosses the discovery
// port.
//
// A datagram is plain text, at most MAXIMUM_DISCOVERY_DATAGRAM_SIZE
// bytes: the line DISCOVERY_TAG, then key=value lines, each ending in a
// newline. A query holds kind=query and pad, filled so the query is the
// largest datagram: a responder answers only a query at least as long as
// its answer, so a query with a forged sender cannot make a host send
// more than it received. An answer holds kind=answer, world, host,
// players, port and build. The parse is strict: another tag, an empty
// line, a line without a newline, an unknown, repeated or missing key, a
// value with a control character or invalid UTF-8, a bad number or an
// over-long datagram is dropped, never trusted.

// One UDP port below the TCP range (DEFAULT_NETWORK_PORT and the nine
// after it), so a firewall passes the range and this one port.
DISCOVERY_PORT :: DEFAULT_NETWORK_PORT - 1
DISCOVERY_TAG :: "mine-oh-belowed-discovery 1"
MAXIMUM_DISCOVERY_DATAGRAM_SIZE :: 512
// The longest world, host or build text an answer carries, in bytes; a
// longer one is cut at a character boundary, so every answer fits.
MAXIMUM_DISCOVERY_TEXT_SIZE :: 128
// The most players an answer may claim: a larger number is malformed.
MAXIMUM_DISCOVERY_PLAYERS :: 1_000_000
// Datagrams read per poll, so a flood cannot hold the frame.
MAXIMUM_DISCOVERY_DATAGRAMS_PER_POLL :: 64

Discovery_Socket :: struct {
	socket: net.UDP_Socket,
	open:   bool,
	port:   int,
}

Discovery_Kind :: enum u8 {
	Query,
	Answer,
}

// The texts are views into the datagram.
Discovery_Message :: struct {
	kind:    Discovery_Kind,
	world:   string,
	host:    string,
	build:   string,
	players: int,
	port:    int,
}

// A datagram and the endpoint it came from.
Discovery_Datagram :: struct {
	bytes:  []byte,
	source: net.Endpoint,
}

// A hosting game's socket on the discovery port of every interface.
// Several games on one machine share the port (the address reuse), and a
// broadcast query reaches each. Port 0 lets the system choose (the tests).
open_discovery_responder :: proc(port: int) -> (discovery: Discovery_Socket, problem: string) {
	socket, create_error := net.make_unbound_udp_socket(.IP4)
	if create_error != nil {
		return {}, fmt.tprintf("cannot open the discovery socket: %v", create_error)
	}
	if option_error := net.set_option(socket, .Reuse_Address, true); option_error != nil {
		net.close(socket)
		return {}, fmt.tprintf("cannot share the discovery port: %v", option_error)
	}
	if bind_error := net.bind(socket, net.Endpoint{address = net.IP4_Any, port = port}); bind_error != nil {
		net.close(socket)
		return {}, fmt.tprintf("cannot listen on the discovery port %d: %v", port, bind_error)
	}
	return finish_discovery_socket(socket)
}

// The Multiplayer screen's socket: any free port, allowed to broadcast.
open_discovery_query :: proc() -> (discovery: Discovery_Socket, problem: string) {
	socket, create_error := net.make_unbound_udp_socket(.IP4)
	if create_error != nil {
		return {}, fmt.tprintf("cannot open the discovery socket: %v", create_error)
	}
	if option_error := net.set_option(socket, .Broadcast, true); option_error != nil {
		net.close(socket)
		return {}, fmt.tprintf("cannot broadcast: %v", option_error)
	}
	if bind_error := net.bind(socket, net.Endpoint{address = net.IP4_Any, port = 0}); bind_error != nil {
		net.close(socket)
		return {}, fmt.tprintf("cannot bind the discovery socket: %v", bind_error)
	}
	return finish_discovery_socket(socket)
}

// Non blocking, and the port it was bound to.
finish_discovery_socket :: proc(socket: net.UDP_Socket) -> (discovery: Discovery_Socket, problem: string) {
	if blocking_error := net.set_blocking(socket, false); blocking_error != nil {
		net.close(socket)
		return {}, fmt.tprintf("cannot make the discovery socket non blocking: %v", blocking_error)
	}
	bound, bound_error := net.bound_endpoint(socket)
	if bound_error != nil {
		net.close(socket)
		return {}, fmt.tprintf("cannot read the discovery socket's port: %v", bound_error)
	}
	return Discovery_Socket{socket = socket, open = true, port = bound.port}, ""
}

close_discovery_socket :: proc(discovery: ^Discovery_Socket) {
	if discovery.open {
		net.close(discovery.socket)
	}
	discovery^ = {}
}

// False when the datagram did not leave (no route, a full buffer): the
// next query or answer tries again.
send_discovery_datagram :: proc(discovery: Discovery_Socket, bytes: []byte, to: net.Endpoint) -> bool {
	if !discovery.open {
		return false
	}
	written, error := net.send_udp(discovery.socket, bytes, to)
	return error == nil && written == len(bytes)
}

// The datagrams waiting, in the allocator, at most
// MAXIMUM_DISCOVERY_DATAGRAMS_PER_POLL. An over-long one (cut by the
// buffer) is dropped here; a receive error (Windows reports an earlier
// answer's unreachable port on the next receive) skips to the next.
receive_discovery_datagrams :: proc(discovery: Discovery_Socket, allocator := context.temp_allocator) -> []Discovery_Datagram {
	datagrams := make([dynamic]Discovery_Datagram, allocator)
	if !discovery.open {
		return datagrams[:]
	}
	buffer: [2 * MAXIMUM_DISCOVERY_DATAGRAM_SIZE]byte
	for _ in 0 ..< MAXIMUM_DISCOVERY_DATAGRAMS_PER_POLL {
		count, source, error := net.recv_udp(discovery.socket, buffer[:])
		#partial switch error {
		case .None:
		case .Would_Block, .Interrupted:
			return datagrams[:]
		case:
			continue
		}
		if count > MAXIMUM_DISCOVERY_DATAGRAM_SIZE {
			continue
		}
		bytes := make([]byte, count, allocator)
		copy(bytes, buffer[:count])
		append(&datagrams, Discovery_Datagram{bytes = bytes, source = source})
	}
	return datagrams[:]
}

// The query, padded to size bytes (the largest datagram by default), in
// the temp allocator. The tests ask for a short one.
encode_discovery_query :: proc(size := MAXIMUM_DISCOVERY_DATAGRAM_SIZE) -> []byte {
	head := fmt.tprintf("%s\nkind=query\npad=", DISCOVERY_TAG)
	padding := max(size - len(head) - 1, 0)
	return transmute([]byte)fmt.tprintf("%s%s\n", head, strings.repeat("x", padding, context.temp_allocator))
}

// The answer, in the temp allocator. The texts are cut to
// MAXIMUM_DISCOVERY_TEXT_SIZE and their line breaks become spaces.
encode_discovery_answer :: proc(world, host, build: string, players, port: int) -> []byte {
	text := fmt.tprintf("%s\nkind=answer\nworld=%s\nhost=%s\nplayers=%d\nport=%d\nbuild=%s\n", DISCOVERY_TAG, discovery_text(world), discovery_text(host), players, port, discovery_text(build))
	return transmute([]byte)text
}

// The text as a value: control characters as spaces, invalid UTF-8 as
// question marks, cut at a character boundary to
// MAXIMUM_DISCOVERY_TEXT_SIZE bytes.
discovery_text :: proc(text: string) -> string {
	text := text
	if !utf8.valid_string(text) {
		bytes := transmute([]byte)strings.clone(text, context.temp_allocator)
		for &character in bytes {
			if character >= 0x80 {
				character = '?'
			}
		}
		text = string(bytes)
	}
	cut := len(text)
	if cut > MAXIMUM_DISCOVERY_TEXT_SIZE {
		cut = MAXIMUM_DISCOVERY_TEXT_SIZE
		for cut > 0 && text[cut] & 0xC0 == 0x80 {
			cut -= 1
		}
	}
	bytes := transmute([]byte)strings.clone(text[:cut], context.temp_allocator)
	for &character in bytes {
		if character < ' ' || character == 0x7F {
			character = ' '
		}
	}
	return string(bytes)
}

// The datagram's message, or ok false for anything but an exact query or
// answer of this protocol.
parse_discovery_datagram :: proc(bytes: []byte) -> (message: Discovery_Message, ok: bool) {
	if len(bytes) > MAXIMUM_DISCOVERY_DATAGRAM_SIZE {
		return {}, false
	}
	text := string(bytes)
	if !strings.has_prefix(text, DISCOVERY_TAG + "\n") {
		return {}, false
	}
	Discovery_Key :: enum u8 {
		Kind,
		World,
		Host,
		Players,
		Port,
		Build,
		Pad,
	}
	seen: bit_set[Discovery_Key]
	values: [Discovery_Key]string
	body := text[len(DISCOVERY_TAG) + 1:]
	for len(body) > 0 {
		end := strings.index_byte(body, '\n')
		if end <= 0 {
			return {}, false
		}
		line := body[:end]
		body = body[end + 1:]
		separator := strings.index_byte(line, '=')
		if separator < 0 || !valid_discovery_value(line[separator + 1:]) {
			return {}, false
		}
		key: Discovery_Key
		switch line[:separator] {
		case "kind":
			key = .Kind
		case "world":
			key = .World
		case "host":
			key = .Host
		case "players":
			key = .Players
		case "port":
			key = .Port
		case "build":
			key = .Build
		case "pad":
			key = .Pad
		case:
			return {}, false
		}
		if key in seen {
			return {}, false
		}
		seen += {key}
		values[key] = line[separator + 1:]
	}
	switch values[.Kind] {
	case "query":
		return Discovery_Message{kind = .Query}, seen == {.Kind, .Pad}
	case "answer":
		if seen != {.Kind, .World, .Host, .Players, .Port, .Build} || !valid_port_text(values[.Port]) {
			return {}, false
		}
		players, players_ok := parse_discovery_count(values[.Players])
		if !players_ok {
			return {}, false
		}
		port, _ := parse_discovery_count(values[.Port])
		return Discovery_Message{kind = .Answer, world = values[.World], host = values[.Host], build = values[.Build], players = players, port = port}, true
	}
	return {}, false
}

// Valid UTF-8 without control characters.
valid_discovery_value :: proc(value: string) -> bool {
	for character in transmute([]byte)value {
		if character < ' ' || character == 0x7F {
			return false
		}
	}
	return utf8.valid_string(value)
}

// Digits only, at most MAXIMUM_DISCOVERY_PLAYERS, checked digit by digit
// so a long number cannot wrap.
parse_discovery_count :: proc(text: string) -> (count: int, ok: bool) {
	if len(text) == 0 {
		return 0, false
	}
	for character in transmute([]byte)text {
		if character < '0' || character > '9' {
			return 0, false
		}
		count = count * 10 + int(character - '0')
		if count > MAXIMUM_DISCOVERY_PLAYERS {
			return 0, false
		}
	}
	return count, true
}

// Where a query goes: the limited broadcast and each interface's subnet
// broadcast (discovery_interface_broadcasts, per system), in the temp
// allocator.
discovery_broadcast_endpoints :: proc(port: int) -> []net.Endpoint {
	endpoints := make([dynamic]net.Endpoint, context.temp_allocator)
	append(&endpoints, net.Endpoint{address = net.IP4_Address{255, 255, 255, 255}, port = port})
	for address in discovery_interface_broadcasts() {
		append(&endpoints, net.Endpoint{address = address, port = port})
	}
	return endpoints[:]
}

// The broadcast address of an IPv4 subnet: the host bits set.
subnet_broadcast :: proc(address: net.IP4_Address, prefix_length: int) -> net.IP4_Address {
	value := u32(address[0]) << 24 | u32(address[1]) << 16 | u32(address[2]) << 8 | u32(address[3])
	host_mask := prefix_length >= 32 ? u32(0) : max(u32) >> uint(max(prefix_length, 0))
	value |= host_mask
	return net.IP4_Address{u8(value >> 24), u8(value >> 16), u8(value >> 8), u8(value)}
}
