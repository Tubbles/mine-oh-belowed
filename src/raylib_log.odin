package game

import "base:runtime"
import "core:c"
import "core:c/libc"
import "core:os"
import "core:strings"
import rl "shared:raylib"

// raylib's trace log (its own lines and GLFW's errors, which raylib logs
// as warnings) goes through log_printf, so the lines reach the log file
// with the game's own, and one class is dropped: GLFW's feature
// unavailable error (GLFW_FEATURE_UNAVAILABLE, 0x0001000C), which every
// window position query and placement raises on Wayland, where windows
// have no position. raylib centres the window at start and reads its
// position to find the current monitor, so on Wayland every display line
// raised one. Nothing is wrong there and nothing can be done, so the line
// is noise (user, 2026-09-28). Installed before InitWindow, since the
// centring runs inside it; raylib applies its log level before calling
// the callback.

SILENCED_TRACE_LOG_PREFIX :: "GLFW: Error: 65548 "
TRACE_LOG_BUFFER_SIZE :: 512

trace_log_is_silenced :: proc(message: string) -> bool {
	return strings.has_prefix(message, SILENCED_TRACE_LOG_PREFIX)
}

// raylib's own prefixes (utils.c, TraceLog), so the console reads as before.
trace_log_level_prefix :: proc(level: rl.TraceLogLevel) -> string {
	switch level {
	case .TRACE:
		return "TRACE"
	case .DEBUG:
		return "DEBUG"
	case .INFO:
		return "INFO"
	case .WARNING:
		return "WARNING"
	case .ERROR:
		return "ERROR"
	case .FATAL:
		return "FATAL"
	case .ALL, .NONE:
		return "LOG"
	}
	return "LOG"
}

// raylib formats nothing before the callback: text is the format and args
// its arguments. raylib exits on a fatal line only without a callback, so
// this one does.
raylib_trace_log_callback :: proc "c" (level: rl.TraceLogLevel, text: cstring, args: ^c.va_list) {
	context = runtime.default_context()
	buffer: [TRACE_LOG_BUFFER_SIZE]u8
	libc.vsnprintf(raw_data(buffer[:]), libc.size_t(len(buffer)), text, args)
	message := string(cstring(raw_data(buffer[:])))
	if trace_log_is_silenced(message) {
		return
	}
	log_printf("%s: %s", trace_log_level_prefix(level), message)
	if level == .FATAL {
		os.exit(1)
	}
}

install_raylib_trace_log :: proc() {
	rl.SetTraceLogCallback(raylib_trace_log_callback)
}
