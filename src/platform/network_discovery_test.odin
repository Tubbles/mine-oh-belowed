package platform

import "core:net"
import "core:strings"
import "core:testing"
import "core:time"

// An answer reads back as written; a query too.
@(test)
test_a_discovery_answer_and_a_query_read_back :: proc(t: ^testing.T) {
	message, ok := parse_discovery_datagram(encode_discovery_answer("Home base", "laptop", "0.0.0 abc1234 2026-10-03", 3, 47_318))
	testing.expect(t, ok)
	testing.expect_value(t, message.kind, Discovery_Kind.Answer)
	testing.expect_value(t, message.world, "Home base")
	testing.expect_value(t, message.host, "laptop")
	testing.expect_value(t, message.build, "0.0.0 abc1234 2026-10-03")
	testing.expect_value(t, message.players, 3)
	testing.expect_value(t, message.port, 47_318)
	message, ok = parse_discovery_datagram(encode_discovery_query())
	testing.expect(t, ok)
	testing.expect_value(t, message.kind, Discovery_Kind.Query)
}

// Anything but an exact query or answer of this protocol is dropped.
@(test)
test_a_malformed_discovery_datagram_is_dropped :: proc(t: ^testing.T) {
	ANSWER :: "kind=answer\nworld=w\nhost=h\nplayers=1\nport=47317\nbuild=b\n"
	testing.expect(t, parse_ok(DISCOVERY_TAG + "\n" + ANSWER))
	malformed := [?]string {
		"mine-oh-belowed-discovery 2\n" + ANSWER,
		"other\n" + ANSWER,
		DISCOVERY_TAG + "\nkind=answer\nworld=w\nhost=h\nplayers=1\nport=47317\n",
		DISCOVERY_TAG + "\n" + ANSWER + "extra=1\n",
		DISCOVERY_TAG + "\n" + ANSWER + "world=again\n",
		DISCOVERY_TAG + "\nkind=answer\nworld=w\nhost=h\nplayers=x\nport=47317\nbuild=b\n",
		DISCOVERY_TAG + "\nkind=answer\nworld=w\nhost=h\nplayers=99999999999999999999999\nport=47317\nbuild=b\n",
		DISCOVERY_TAG + "\nkind=answer\nworld=w\nhost=h\nplayers=1\nport=0\nbuild=b\n",
		DISCOVERY_TAG + "\nkind=answer\nworld=w\nhost=h\nplayers=1\nport=65536\nbuild=b\n",
		DISCOVERY_TAG + "\nkind=answer\nworld=w\nhost=h\nplayers=1\nport=47317\nbuild=b",
		DISCOVERY_TAG + "\nkind=query\nworld=w\n",
		DISCOVERY_TAG + "\nkind=shout\n",
		DISCOVERY_TAG + "\nno separator\n",
		DISCOVERY_TAG + "\nkind=query\n",
		DISCOVERY_TAG + "\n" + ANSWER + "\n",
		DISCOVERY_TAG + "\n\n" + ANSWER,
		DISCOVERY_TAG + "\nkind=answer\nworld=w\ttab\nhost=h\nplayers=1\nport=47317\nbuild=b\n",
		DISCOVERY_TAG + "\nkind=answer\nworld=w\nhost=h\x7f\nplayers=1\nport=47317\nbuild=b\n",
		DISCOVERY_TAG + "\nkind=answer\nworld=\xff\xfe\nhost=h\nplayers=1\nport=47317\nbuild=b\n",
		DISCOVERY_TAG + "\nkind=answer\nworld=\xc3\nhost=h\nplayers=1\nport=47317\nbuild=b\n",
		DISCOVERY_TAG + "\nkind=answer\nworld=w\nhost=h\nplayers=1\nport=47317\nbuild=b\npad=x\n",
		DISCOVERY_TAG + "\n",
		DISCOVERY_TAG,
		"",
	}
	for text in malformed {
		testing.expectf(t, !parse_ok(text), "accepted %q", text)
	}
	long := strings.concatenate({DISCOVERY_TAG, "\n", ANSWER, strings.repeat("x", MAXIMUM_DISCOVERY_DATAGRAM_SIZE, context.temp_allocator)}, context.temp_allocator)
	testing.expect(t, !parse_ok(long))
}

parse_ok :: proc(text: string) -> bool {
	_, ok := parse_discovery_datagram(transmute([]byte)text)
	return ok
}

// The longest texts still make an answer that fits, cut at a character
// boundary, with no line break of their own.
@(test)
test_an_answer_of_the_longest_texts_fits :: proc(t: ^testing.T) {
	long := strings.repeat("é", MAXIMUM_DISCOVERY_TEXT_SIZE, context.temp_allocator)
	bytes := encode_discovery_answer(long, "two\nlines", long, MAXIMUM_DISCOVERY_PLAYERS, 65_535)
	testing.expect(t, len(bytes) <= MAXIMUM_DISCOVERY_DATAGRAM_SIZE)
	message, ok := parse_discovery_datagram(bytes)
	testing.expect(t, ok)
	testing.expect_value(t, len(message.world), MAXIMUM_DISCOVERY_TEXT_SIZE)
	testing.expect(t, strings.has_suffix(message.world, "é"))
	testing.expect_value(t, message.host, "two lines")
}

@(test)
test_a_subnet_broadcast_sets_the_host_bits :: proc(t: ^testing.T) {
	testing.expect_value(t, subnet_broadcast({192, 168, 1, 20}, 24), net.IP4_Address{192, 168, 1, 255})
	testing.expect_value(t, subnet_broadcast({10, 1, 2, 3}, 8), net.IP4_Address{10, 255, 255, 255})
	testing.expect_value(t, subnet_broadcast({172, 16, 5, 9}, 20), net.IP4_Address{172, 16, 15, 255})
	testing.expect_value(t, subnet_broadcast({10, 0, 0, 1}, 32), net.IP4_Address{10, 0, 0, 1})
}

// A query over the loopback reaches a responder, and the answer sent to
// the query's source comes back.
@(test)
test_a_discovery_query_and_answer_cross_the_loopback :: proc(t: ^testing.T) {
	responder, problem := open_discovery_responder(0)
	if !testing.expect_value(t, problem, "") {
		return
	}
	defer close_discovery_socket(&responder)
	query: Discovery_Socket
	query, problem = open_discovery_query()
	if !testing.expect_value(t, problem, "") {
		return
	}
	defer close_discovery_socket(&query)
	testing.expect(t, send_discovery_datagram(query, encode_discovery_query(), net.Endpoint{address = net.IP4_Loopback, port = responder.port}))
	answered := false
	start := time.tick_now()
	for !answered && time.tick_since(start) < NETWORK_TEST_TIMEOUT {
		for datagram in receive_discovery_datagrams(responder) {
			message, ok := parse_discovery_datagram(datagram.bytes)
			if ok && message.kind == .Query {
				send_discovery_datagram(responder, encode_discovery_answer("world", "machine", "build", 1, 47_317), datagram.source)
			}
		}
		for datagram in receive_discovery_datagrams(query) {
			message, ok := parse_discovery_datagram(datagram.bytes)
			answered ||= ok && message.kind == .Answer && message.world == "world"
		}
		time.sleep(time.Millisecond)
	}
	testing.expect(t, answered)
}

// A port another listener holds is skipped for the next of the range.
@(test)
test_a_taken_port_is_skipped_for_the_next_free_one :: proc(t: ^testing.T) {
	taken, problem := listen_on_port(0, .Loopback)
	if !testing.expect_value(t, problem, "") {
		return
	}
	defer close_listener(&taken)
	listener: Network_Listener
	listener, problem = listen_on_free_port(taken.port, 10, .Loopback)
	testing.expect_value(t, problem, "")
	defer close_listener(&listener)
	testing.expect(t, listener.port > taken.port && listener.port < taken.port + 10)
	_, problem = listen_on_free_port(taken.port, 1, .Loopback)
	testing.expect(t, problem != "")
}

// No prefix of a valid query or answer reads as a message, the tag line
// alone included (its slice once ran past the end).
@(test)
test_every_prefix_of_a_valid_datagram_is_dropped :: proc(t: ^testing.T) {
	for datagram in ([?][]byte{encode_discovery_query(), encode_discovery_answer("Home base", "laptop", "build", 2, 47_317)}) {
		for length in 0 ..< len(datagram) {
			_, ok := parse_discovery_datagram(datagram[:length])
			testing.expectf(t, !ok, "a prefix of %d bytes was accepted", length)
		}
		_, ok := parse_discovery_datagram(datagram)
		testing.expect(t, ok)
	}
	tag_line := DISCOVERY_TAG + "\n"
	testing.expect(t, !parse_ok(tag_line))
}

// The query is the largest datagram, so it is never shorter than an
// answer; texts of invalid UTF-8 still make an answer that reads back.
@(test)
test_the_query_is_at_least_as_long_as_any_answer :: proc(t: ^testing.T) {
	query := encode_discovery_query()
	testing.expect_value(t, len(query), MAXIMUM_DISCOVERY_DATAGRAM_SIZE)
	long := strings.repeat("W", 2 * MAXIMUM_DISCOVERY_TEXT_SIZE, context.temp_allocator)
	answer := encode_discovery_answer(long, long, long, MAXIMUM_DISCOVERY_PLAYERS, 65_535)
	testing.expect(t, len(query) >= len(answer))
	message, ok := parse_discovery_datagram(encode_discovery_answer("bad \xff\xfe name", "h", "b", 1, 47_317))
	testing.expect(t, ok)
	testing.expect_value(t, message.world, "bad ?? name")
}
