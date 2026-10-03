#+build windows
package platform

import "core:net"
import "core:os"
import win "core:sys/windows"

// The Windows side of network_discovery.odin: the adapters' subnet
// broadcast addresses through GetAdaptersAddresses (core:net's interface
// list leaves the prefix length out), and the machine's name from
// COMPUTERNAME.

// GetAdaptersAddresses asks for a larger buffer at most this often.
MAXIMUM_ADAPTER_LIST_TRIES :: 3
ADAPTER_BUFFER_OVERFLOW :: 111
SOFTWARE_LOOPBACK_ADAPTER :: 24

// The broadcast address of every IPv4 address of an adapter that is up
// and not the loopback, in the temp allocator. None when the call fails.
discovery_interface_broadcasts :: proc() -> []net.IP4_Address {
	addresses := make([dynamic]net.IP4_Address, context.temp_allocator)
	size: u32 = 16 * 1024
	// Words, so the adapter records are aligned.
	buffer: []u64
	result: u32 = ADAPTER_BUFFER_OVERFLOW
	for _ in 0 ..< MAXIMUM_ADAPTER_LIST_TRIES {
		buffer = make([]u64, size / 8 + 1, context.temp_allocator)
		result = win.get_adapters_addresses(.IPv4, {}, nil, ([^]win.IP_Adapter_Addresses)(raw_data(buffer)), &size)
		if result != ADAPTER_BUFFER_OVERFLOW {
			break
		}
	}
	if result != 0 {
		return addresses[:]
	}
	for adapter := (^win.IP_Adapter_Addresses)(raw_data(buffer)); adapter != nil; adapter = adapter.Next {
		if adapter.OperStatus != .Up || adapter.IfType == SOFTWARE_LOOPBACK_ADAPTER {
			continue
		}
		for unicast := adapter.FirstUnicastAddress; unicast != nil; unicast = unicast.Next {
			socket_address := unicast.Address.lpSockaddr
			if socket_address == nil || unicast.Address.iSockaddrLength < size_of(win.sockaddr_in) || socket_address.sa_family != win.ADDRESS_FAMILY(win.AF_INET) {
				continue
			}
			ip4 := (^win.sockaddr_in)(socket_address).sin_addr
			bytes := transmute([4]u8)ip4
			append(&addresses, subnet_broadcast(net.IP4_Address(bytes), int(unicast.OnLinkPrefixLength)))
		}
	}
	return addresses[:]
}

// The machine's name as the discovery shows it, in the temp allocator.
discovery_machine_name :: proc() -> string {
	return os.get_env("COMPUTERNAME", context.temp_allocator)
}
