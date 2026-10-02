#+build windows
package platform

// The Windows side of stop_signal_posix.odin: no handler is installed (a
// console control handler would need the Windows system package, not
// wanted for one flag yet), so Ctrl+C ends a Windows server without the
// save on stop; the autosave interval still saves.

install_stop_handlers :: proc() {}

stop_requested :: proc() -> bool {
	return false
}
