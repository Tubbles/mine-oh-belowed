package platform

import "core:fmt"
import "core:net"
import "core:testing"
import "core:time"

NETWORK_TEST_TIMEOUT :: 10 * time.Second

// A host and a client over the loopback: messages arrive whole, in order,
// both ways, a large one too, and a closed peer is noticed.
@(test)
test_messages_cross_a_loopback_connection :: proc(t: ^testing.T) {
	listener, client, host, ok := open_loopback_pair(t)
	if !ok {
		return
	}
	defer close_listener(&listener)
	defer destroy_connection(&client)
	defer destroy_connection(&host)
	large := make([]byte, 3 * NETWORK_RECEIVE_CHUNK_SIZE + 5, context.temp_allocator)
	for &value, index in large {
		value = byte(index % 251)
	}
	send_message(&client, transmute([]byte)string("first"))
	send_message(&client, large)
	send_message(&host, transmute([]byte)string("back"))
	received: [dynamic][]byte
	received.allocator = context.temp_allocator
	answer: []byte
	start := time.tick_now()
	for (len(received) < 2 || answer == nil) && time.tick_since(start) < NETWORK_TEST_TIMEOUT {
		poll_connection(&host)
		poll_connection(&client)
		for payload in take_message(&host, context.temp_allocator) {
			append(&received, payload)
		}
		if payload, answered := take_message(&client, context.temp_allocator); answered {
			answer = payload
		}
		time.sleep(time.Millisecond)
	}
	if !testing.expect_value(t, len(received), 2) {
		return
	}
	testing.expect_value(t, string(received[0]), "first")
	testing.expect_value(t, len(received[1]), len(large))
	testing.expect(t, string(received[1]) == string(large))
	testing.expect_value(t, string(answer), "back")
	close_connection(&client)
	start = time.tick_now()
	for host.open && time.tick_since(start) < NETWORK_TEST_TIMEOUT {
		poll_connection(&host)
		time.sleep(time.Millisecond)
	}
	testing.expect(t, !host.open)
}

@(test)
test_a_join_address_port_is_range_checked :: proc(t: ^testing.T) {
	endpoint, problem := network_endpoint("127.0.0.1:4000")
	testing.expect_value(t, problem, "")
	testing.expect_value(t, endpoint.port, 4000)
	endpoint, problem = network_endpoint("127.0.0.1")
	testing.expect_value(t, problem, "")
	testing.expect_value(t, endpoint.port, DEFAULT_NETWORK_PORT)
	for address in ([?]string{"127.0.0.1:0", "127.0.0.1:65536", "127.0.0.1:-1", "127.0.0.1:", "127.0.0.1:18446744073709551696"}) {
		_, problem = network_endpoint(address)
		testing.expectf(t, problem != "", "%s accepted", address)
	}
}

// A listener on the loopback and a connection to it, both ends.
open_loopback_pair :: proc(t: ^testing.T) -> (listener: Network_Listener, client, host: Network_Connection, ok: bool) {
	problem: string
	listener, problem = listen_on_port(0, .Loopback)
	if !testing.expect_value(t, problem, "") {
		return
	}
	testing.expect(t, listener.port != 0)
	client, problem = connect_to(fmt.tprintf("127.0.0.1:%d", listener.port))
	if !testing.expect_value(t, problem, "") {
		close_listener(&listener)
		return
	}
	start := time.tick_now()
	for time.tick_since(start) < NETWORK_TEST_TIMEOUT {
		accepted: bool
		if host, accepted = accept_connection(&listener); accepted {
			break
		}
		time.sleep(time.Millisecond)
	}
	ok = testing.expect(t, host.open)
	if !ok {
		destroy_connection(&client)
		close_listener(&listener)
	}
	return
}

// Polls until the connection received at least count bytes in all.
poll_until_received :: proc(connection: ^Network_Connection, count: int) {
	start := time.tick_now()
	for connection.received_total < count && time.tick_since(start) < NETWORK_TEST_TIMEOUT {
		poll_connection(connection)
		time.sleep(time.Millisecond)
	}
}

// A length prefix split over two reads: no message until the rest comes.
@(test)
test_a_length_split_across_two_polls_waits_for_the_rest :: proc(t: ^testing.T) {
	listener, client, host, ok := open_loopback_pair(t)
	if !ok {
		return
	}
	defer close_listener(&listener)
	defer destroy_connection(&client)
	defer destroy_connection(&host)
	bytes := [?]byte{5, 0, 0, 0, 'h', 'e', 'l', 'l', 'o'}
	net.send_tcp(client.socket, bytes[:2])
	poll_until_received(&host, 2)
	_, early := take_message(&host, context.temp_allocator)
	testing.expect(t, !early)
	net.send_tcp(client.socket, bytes[2:])
	poll_until_received(&host, len(bytes))
	payload, whole := take_message(&host, context.temp_allocator)
	testing.expect(t, whole)
	testing.expect_value(t, string(payload), "hello")
}

// A length prefix over the limit closes the connection before anything
// is allocated for it.
@(test)
test_an_oversized_length_closes_the_connection :: proc(t: ^testing.T) {
	connection := Network_Connection{open = false}
	defer delete(connection.received)
	length := u32(MAXIMUM_NETWORK_MESSAGE_SIZE + 1)
	for index in 0 ..< NETWORK_LENGTH_SIZE {
		append(&connection.received, byte(length >> (8 * uint(index))))
	}
	_, ok := take_message(&connection)
	testing.expect(t, !ok)
	testing.expect_value(t, len(connection.received), 0)
}
