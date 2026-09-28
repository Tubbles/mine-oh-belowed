package game

import "core:testing"

@(test)
test_trace_log_silences_glfw_feature_unavailable :: proc(t: ^testing.T) {
	testing.expect(t, trace_log_is_silenced("GLFW: Error: 65548 Description: Wayland: The platform does not provide the window position"))
	testing.expect(t, trace_log_is_silenced("GLFW: Error: 65548 Description: Wayland: The platform does not support setting the window position"))
	testing.expect(t, !trace_log_is_silenced("GLFW: Error: 65544 Description: Wayland: Failed to connect to display"))
	testing.expect(t, !trace_log_is_silenced("FILEIO: [missing.png] Failed to open file"))
	testing.expect_value(t, trace_log_level_prefix(.WARNING), "WARNING")
	testing.expect_value(t, trace_log_level_prefix(.INFO), "INFO")
}
