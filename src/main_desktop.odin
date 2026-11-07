#+build !linux:android
package game

// The entry point everywhere but Android, whose build has none: Odin
// dev-2026-11 refuses a main there that nothing calls through
// intrinsics.__entry_point, and main_android.odin's __wrap_main runs
// game_main (0315).
main :: proc() {
	game_main()
}
