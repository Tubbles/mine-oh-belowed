#+build !windows
package platform

import "core:sync"
import "core:sys/posix"

// SIGINT and SIGTERM ask the headless server to stop (work item 0177): the
// handler only sets a flag, the server's loop saves and exits
// (session_server.odin). Paired with stop_signal_windows.odin, since
// core:sys/posix stays out of the Windows build (logging_posix.odin).

global_stop_requested: bool

stop_signal_handler :: proc "c" (signal: posix.Signal) {
	sync.atomic_store(&global_stop_requested, true)
}

// Not on Android, for the sigaction layout logging_posix.odin describes;
// the server does not run there.
install_stop_handlers :: proc() {
	when ODIN_PLATFORM_SUBTARGET != .Android {
		action := posix.sigaction_t {
			sa_handler = stop_signal_handler,
		}
		posix.sigemptyset(&action.sa_mask)
		posix.sigaction(.SIGINT, &action, nil)
		posix.sigaction(.SIGTERM, &action, nil)
	}
}

stop_requested :: proc() -> bool {
	return sync.atomic_load(&global_stop_requested)
}
