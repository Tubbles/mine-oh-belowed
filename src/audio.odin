package game

import "core:encoding/json"
import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:strings"
import rl "vendor:raylib"

// Sound (work item 0068): the sound table in data/sounds/sounds.sjson and
// a small mixer over raylib audio. Effects are short sounds played once,
// never twice within EFFECT_MINIMUM_GAP_SECONDS so repeats do not stack;
// loops stream and approach a target volume the frame sets
// (set_loop_target) over LOOP_FADE_SECONDS, so the biome ambience
// crossfades and the rain and the hum fade in and out. The table, the
// gap rule and the volume approach are pure; only the device, loading
// and playing touch raylib, and without an audio device every call is a
// no op. Sound is presentation: the simulation never sees any of it.
// A biome ambience is a loop or a set of effect variants the sound events
// play in clusters (work item 0089); day_only keeps the latter to the day.

SOUNDS_DIRECTORY :: "sounds"
SOUNDS_FILE_NAME :: "sounds.sjson"
SOUND_FILE_EXTENSION :: ".wav"
EFFECT_MINIMUM_GAP_SECONDS :: 0.04
// A loop goes from silent to full (or back) over this long.
LOOP_FADE_SECONDS :: 0.5
// Before the first play, so the first play always passes the gap rule.
NEVER_PLAYED_SECONDS :: -1.0

Sound_Kind :: enum u8 {
	Effect,
	Loop,
}

@(rodata)
sound_kind_names := [Sound_Kind]string {
	.Effect = "effect",
	.Loop   = "loop",
}

Sound_Definition :: struct {
	id:       string,
	file:     string,
	volume:   f32,
	kind:     string,
	day_only: bool,
}

Sounds_File :: struct {
	sounds: []Sound_Definition,
}

Sound_Entry :: struct {
	id:       string,
	file:     string,
	volume:   f32,
	kind:     Sound_Kind,
	day_only: bool,
}

Sound_Table :: struct {
	entries: []Sound_Entry,
}

// The settings' volumes, 0 to 1 each.
Audio_Volumes :: struct {
	master:    f32,
	effects:   f32,
	ambience:  f32,
}

// The pure half of the mixer, indexed like the table's entries: when
// each effect last played on the mixer's clock, and each loop's volume
// and the target the frame set.
Mixer_State :: struct {
	clock_seconds: f64,
	last_played:   []f64,
	loop_volumes:  []f32,
	loop_targets:  []f32,
}

// The table, the loaded sounds and the mixer state live in arena, which
// a sounds reload replaces. sounds holds the effects, music the loops,
// each zero at the other kind's indices.
Audio_Mixer :: struct {
	device_ready: bool,
	arena:        ^virtual.Arena,
	table:        Sound_Table,
	sounds:       []rl.Sound,
	music:        []rl.Music,
	state:        Mixer_State,
	volumes:      Audio_Volumes,
}

parse_sounds_file :: proc(data: []byte, allocator := context.allocator) -> (file: Sounds_File, error: json.Unmarshal_Error) {
	error = json.unmarshal(data, &file, .SJSON, allocator)
	return
}

validate_sound_definition :: proc(definition: Sound_Definition) -> string {
	switch {
	case definition.id == "":
		return "a sound has no id"
	case definition.file == "":
		return fmt.tprintf("sound %q has no file", definition.id)
	case definition.volume <= 0 || definition.volume > 1:
		return fmt.tprintf("sound %q has volume %v outside 0 to 1", definition.id, definition.volume)
	}
	return ""
}

resolve_sound_table :: proc(file: Sounds_File, allocator := context.allocator) -> (table: Sound_Table, problem: string) {
	entries := make([]Sound_Entry, len(file.sounds), allocator)
	for definition, index in file.sounds {
		if problem = validate_sound_definition(definition); problem != "" {
			return {}, problem
		}
		kind, found := parse_named_enum(sound_kind_names, definition.kind)
		if !found {
			return {}, fmt.tprintf("sound %q has unknown kind %q", definition.id, definition.kind)
		}
		if _, listed := find_sound(Sound_Table{entries = entries[:index]}, definition.id); listed {
			return {}, fmt.tprintf("sound id %q is listed twice", definition.id)
		}
		entries[index] = Sound_Entry{id = definition.id, file = definition.file, volume = definition.volume, kind = kind, day_only = definition.day_only}
	}
	return Sound_Table{entries = entries}, ""
}

find_sound :: proc(table: Sound_Table, id: string) -> (index: int, found: bool) {
	for entry, entry_index in table.entries {
		if entry.id == id {
			return entry_index, true
		}
	}
	return -1, false
}

sound_listed :: proc(table: Sound_Table, id: string) -> bool {
	_, found := find_sound(table, id)
	return found
}

sound_file_path :: proc(data_directory, file: string) -> string {
	return join_save_path(data_directory, SOUNDS_DIRECTORY, file)
}

// Every listed file is on disk.
missing_sound_file :: proc(table: Sound_Table, data_directory: string) -> string {
	for entry in table.entries {
		if path := sound_file_path(data_directory, entry.file); !os.exists(path) {
			return fmt.tprintf("sound %q: %s does not exist", entry.id, path)
		}
	}
	return ""
}

// The table from data/sounds/sounds.sjson, its files checked; no raylib.
load_sound_table :: proc(data_directory: string, allocator := context.allocator) -> (table: Sound_Table, problem: string) {
	path := join_save_path(data_directory, SOUNDS_DIRECTORY, SOUNDS_FILE_NAME)
	data, read_error := os.read_entire_file(path, context.temp_allocator)
	if read_error != nil {
		return {}, fmt.tprintf("cannot read %s: %v", path, read_error)
	}
	file, error := parse_sounds_file(data, allocator)
	if error != nil {
		return {}, fmt.tprintf("cannot parse %s: %v", path, error)
	}
	if table, problem = resolve_sound_table(file, allocator); problem != "" {
		return {}, problem
	}
	return table, missing_sound_file(table, data_directory)
}

// A loop ambience_<name> or its variants ambience_<name>_1 and up.
ambience_listed :: proc(table: Sound_Table, id: string) -> bool {
	return sound_listed(table, id) || ambience_variant_count(table, id) > 0
}

// The blocks' footsteps and the biomes' ambience are in the table.
validate_sound_references :: proc(table: Sound_Table, blocks: Block_Registry, biomes: []Biome) -> string {
	for definition, block in blocks.definitions {
		if id := footstep_sound_id(block_sound_material(blocks, Block_Id(block))); !sound_listed(table, id) {
			return fmt.tprintf("block %q has sound_material %q, but %s lists no %q", definition.id, block_sound_material(blocks, Block_Id(block)), SOUNDS_FILE_NAME, id)
		}
	}
	for biome in biomes {
		if id := ambience_sound_id(biome.definition.ambience); id != "" && !ambience_listed(table, id) {
			return fmt.tprintf("biome %q has ambience %q, but %s lists no %q nor %q", biome.definition.id, biome.definition.ambience, SOUNDS_FILE_NAME, id, ambience_variant_sound_id(id, 1))
		}
	}
	return ""
}

make_mixer_state :: proc(entry_count: int, allocator := context.allocator) -> Mixer_State {
	state := Mixer_State {
		last_played  = make([]f64, entry_count, allocator),
		loop_volumes = make([]f32, entry_count, allocator),
		loop_targets = make([]f32, entry_count, allocator),
	}
	for &played in state.last_played {
		played = NEVER_PLAYED_SECONDS
	}
	return state
}

effect_gap_allows :: proc(last_played, now: f64) -> bool {
	return last_played == NEVER_PLAYED_SECONDS || now - last_played >= EFFECT_MINIMUM_GAP_SECONDS
}

// Records the play when the gap rule allows it.
mixer_request_effect :: proc(state: ^Mixer_State, index: int) -> bool {
	if !effect_gap_allows(state.last_played[index], state.clock_seconds) {
		return false
	}
	state.last_played[index] = state.clock_seconds
	return true
}

// Several requests in a frame keep the loudest.
mixer_set_loop_target :: proc(state: ^Mixer_State, index: int, volume: f32) {
	state.loop_targets[index] = max(state.loop_targets[index], clamp(volume, 0, 1))
}

// A linear step of seconds / LOOP_FADE_SECONDS towards the target.
approach_loop_volume :: proc(current, target, seconds: f32) -> f32 {
	step := max(seconds, 0) / LOOP_FADE_SECONDS
	if current < target {
		return min(current + step, target)
	}
	return max(current - step, target)
}

// Advances the clock and every loop's volume towards the frame's target,
// then clears the targets for the next frame: a loop nobody asks for
// fades out.
advance_mixer_state :: proc(state: ^Mixer_State, seconds: f32) {
	state.clock_seconds += f64(max(seconds, 0))
	for &volume, index in state.loop_volumes {
		volume = approach_loop_volume(volume, state.loop_targets[index], seconds)
		state.loop_targets[index] = 0
	}
}

audio_volumes :: proc(settings: Settings) -> Audio_Volumes {
	return Audio_Volumes{master = clamp(settings.master_volume, 0, 1), effects = clamp(settings.effects_volume, 0, 1), ambience = clamp(settings.ambience_volume, 0, 1)}
}

// Loops and the clustered ambience calls are ambience, the rest effects.
sound_channel_volume :: proc(entry: Sound_Entry, volumes: Audio_Volumes) -> f32 {
	if entry.kind == .Loop || strings.has_prefix(entry.id, AMBIENCE_SOUND_PREFIX) {
		return volumes.ambience
	}
	return volumes.effects
}

// The level raylib gets: the entry's volume, the play's or the loop's,
// the channel's and the master volume.
sound_output_volume :: proc(entry: Sound_Entry, volume: f32, volumes: Audio_Volumes) -> f32 {
	return clamp(entry.volume * volume * sound_channel_volume(entry, volumes) * volumes.master, 0, 1)
}

// Raylib.

// After the window. Without a device the mixer stays silent.
init_audio :: proc(data_directory: string, blocks: Block_Registry, biomes: []Biome, settings: Settings) -> Audio_Mixer {
	rl.InitAudioDevice()
	if !rl.IsAudioDeviceReady() {
		log_printf("audio: no audio device, the game stays silent")
		return {}
	}
	mixer := Audio_Mixer{device_ready = true, volumes = audio_volumes(settings)}
	if problem := load_mixer_sounds(&mixer, data_directory, blocks, biomes); problem != "" {
		log_printf("error: sounds: %s", problem)
	}
	return mixer
}

// Loads the table and its files into a new arena and, on success, puts
// them in place of the old ones. On a problem the old sounds stay.
load_mixer_sounds :: proc(mixer: ^Audio_Mixer, data_directory: string, blocks: Block_Registry, biomes: []Biome) -> string {
	if !mixer.device_ready {
		return ""
	}
	arena := new_growing_arena()
	if arena == nil {
		return "cannot reserve memory for the sounds"
	}
	allocator := virtual.arena_allocator(arena)
	table, problem := load_sound_table(data_directory, allocator)
	if problem == "" {
		problem = validate_sound_references(table, blocks, biomes)
	}
	if problem != "" {
		destroy_arena(arena)
		return problem
	}
	unload_mixer_sounds(mixer)
	mixer.arena, mixer.table = arena, table
	mixer.sounds = make([]rl.Sound, len(table.entries), allocator)
	mixer.music = make([]rl.Music, len(table.entries), allocator)
	mixer.state = make_mixer_state(len(table.entries), allocator)
	for entry, index in table.entries {
		path := fmt.ctprintf("%s", sound_file_path(data_directory, entry.file))
		switch entry.kind {
		case .Effect:
			mixer.sounds[index] = rl.LoadSound(path)
		case .Loop:
			mixer.music[index] = rl.LoadMusicStream(path)
		}
	}
	return ""
}

unload_mixer_sounds :: proc(mixer: ^Audio_Mixer) {
	for entry, index in mixer.table.entries {
		switch entry.kind {
		case .Effect:
			rl.UnloadSound(mixer.sounds[index])
		case .Loop:
			rl.UnloadMusicStream(mixer.music[index])
		}
	}
	destroy_arena(mixer.arena)
	device_ready, volumes := mixer.device_ready, mixer.volumes
	mixer^ = Audio_Mixer{device_ready = device_ready, volumes = volumes}
}

shutdown_audio :: proc(mixer: ^Audio_Mixer) {
	if !mixer.device_ready {
		return
	}
	unload_mixer_sounds(mixer)
	rl.CloseAudioDevice()
	mixer^ = {}
}

// volume scales the entry's level, pitch 1 is as recorded. An unknown id
// or a loop plays nothing.
play_effect :: proc(mixer: ^Audio_Mixer, id: string, volume: f32 = 1, pitch: f32 = 1) {
	if !mixer.device_ready {
		return
	}
	index, found := find_sound(mixer.table, id)
	if !found || mixer.table.entries[index].kind != .Effect || !mixer_request_effect(&mixer.state, index) {
		return
	}
	sound := mixer.sounds[index]
	rl.SetSoundVolume(sound, sound_output_volume(mixer.table.entries[index], volume, mixer.volumes))
	rl.SetSoundPitch(sound, pitch)
	rl.PlaySound(sound)
}

// The loop plays at this level this frame (after the fade); a loop no
// frame asks for fades out.
set_loop_target :: proc(mixer: ^Audio_Mixer, id: string, volume: f32) {
	if !mixer.device_ready {
		return
	}
	if index, found := find_sound(mixer.table, id); found && mixer.table.entries[index].kind == .Loop {
		mixer_set_loop_target(&mixer.state, index, volume)
	}
}

// Once a frame, after the frame's requests: the fades, the loops' levels
// and their streams. A silent loop stops, so it costs nothing.
update_audio :: proc(mixer: ^Audio_Mixer, settings: Settings, seconds: f32) {
	if !mixer.device_ready {
		return
	}
	mixer.volumes = audio_volumes(settings)
	advance_mixer_state(&mixer.state, seconds)
	for entry, index in mixer.table.entries {
		if entry.kind != .Loop {
			continue
		}
		music := mixer.music[index]
		volume := mixer.state.loop_volumes[index]
		playing := rl.IsMusicStreamPlaying(music)
		switch {
		case volume <= 0 && playing:
			rl.StopMusicStream(music)
		case volume > 0 && !playing:
			rl.PlayMusicStream(music)
		}
		if volume > 0 {
			rl.SetMusicVolume(music, sound_output_volume(entry, volume, mixer.volumes))
			rl.UpdateMusicStream(music)
		}
	}
}
