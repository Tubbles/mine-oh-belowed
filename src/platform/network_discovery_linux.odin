#+build linux
package platform

import "core:net"
import "core:strings"
import "core:sys/linux"

// The Linux and Android side of network_discovery.odin: the interfaces'
// broadcast addresses through the SIOCGIFCONF, SIOCGIFFLAGS and
// SIOCGIFBRDADDR requests (core:net does not enumerate interfaces on
// Linux), and the machine's name from uname. On the phone the name is
// usually "localhost".

SIOCGIFCONF :: 0x8912
SIOCGIFFLAGS :: 0x8913
SIOCGIFBRDADDR :: 0x8919
INTERFACE_UP :: 0x1
INTERFACE_BROADCAST :: 0x2
INTERFACE_LOOPBACK :: 0x8
// The interfaces asked for at most.
MAXIMUM_DISCOVERY_INTERFACES :: 32

// struct ifreq: the name, then a union whose largest member is 24 bytes
// on 64 bit targets.
Interface_Request :: struct {
	name:  [16]u8,
	value: [24]u8,
}
#assert(size_of(Interface_Request) == 40)

// struct ifconf.
Interface_Configuration :: struct {
	length:   i32,
	requests: [^]Interface_Request,
}

// The broadcast address of every interface that is up, broadcasts and is
// not the loopback, in the temp allocator. None when the requests fail.
discovery_interface_broadcasts :: proc() -> []net.IP4_Address {
	addresses := make([dynamic]net.IP4_Address, context.temp_allocator)
	socket, socket_error := linux.socket(.INET, .DGRAM, {.CLOEXEC}, .UDP)
	if socket_error != .NONE {
		return addresses[:]
	}
	defer linux.close(socket)
	requests: [MAXIMUM_DISCOVERY_INTERFACES]Interface_Request
	configuration := Interface_Configuration{length = i32(size_of(requests)), requests = &requests[0]}
	if !interface_request(socket, SIOCGIFCONF, &configuration) {
		return addresses[:]
	}
	count := min(int(configuration.length) / size_of(Interface_Request), MAXIMUM_DISCOVERY_INTERFACES)
	for index in 0 ..< count {
		request := requests[index]
		if !interface_request(socket, SIOCGIFFLAGS, &request) {
			continue
		}
		flags := u16(request.value[0]) | u16(request.value[1]) << 8
		if flags & INTERFACE_UP == 0 || flags & INTERFACE_BROADCAST == 0 || flags & INTERFACE_LOOPBACK != 0 {
			continue
		}
		if !interface_request(socket, SIOCGIFBRDADDR, &request) {
			continue
		}
		// A sockaddr_in: the family, the port, then the address.
		if u16(request.value[0]) | u16(request.value[1]) << 8 != u16(linux.Address_Family.INET) {
			continue
		}
		append(&addresses, net.IP4_Address{request.value[4], request.value[5], request.value[6], request.value[7]})
	}
	return addresses[:]
}

interface_request :: proc(socket: linux.Fd, request: u32, argument: rawptr) -> bool {
	return int(linux.ioctl(socket, request, uintptr(argument))) == 0
}

// The machine's name as the discovery shows it, in the temp allocator.
discovery_machine_name :: proc() -> string {
	name: linux.UTS_Name
	if linux.uname(&name) != .NONE {
		return ""
	}
	return strings.clone(string(cstring(&name.nodename[0])), context.temp_allocator)
}
