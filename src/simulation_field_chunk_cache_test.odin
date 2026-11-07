package game

import "base:runtime"
import "core:slice"
import "core:sync"
import "core:testing"

// The field chunks the test process generated (work item 0318), shared
// by every test's sessions. A session's chunk is fixed by the seed, the
// spacing, the planet's generation record, the overlay flag and the
// coordinate: the record holds what generation reads off a planet
// (generation_planet_record.odin's header), and what a session derives
// besides comes from the seed and the record. So a session staged from
// the cache holds the bytes it would generate. The entries live on
// runtime.heap_allocator() for the whole process: the runner frees each
// test's allocator after the test (free_all on the thread's rollback
// stack) and reports what is left in it as leaked, so a fixture made in
// one test's allocator would vanish under the next (data_strings.odin's
// missing key records are the precedent).

// Past it the cache claims nothing and the tests generate as before: the
// slow tier fills about 950 entries (350 MiB).
FIELD_CHUNK_CACHE_CAPACITY :: 2048

Field_Chunk_Cache_Key :: struct {
	seed:                u64,
	spacing_millimetres: int,
	record:              Planet_Generation_Record,
	crater_overlay:      bool,
	coordinate:          Field_Chunk_Coordinate,
}

Field_Chunk_Cache_Entry :: struct {
	// The springs cloned on the heap.
	key:   Field_Chunk_Cache_Key,
	// nil while the test that claimed it generates it.
	chunk: ^Field_Chunk,
}

Field_Chunk_Cache :: struct {
	mutex:   sync.Mutex,
	// Made with the heap allocator on first use, as each bucket.
	entries: map[Field_Chunk_Coordinate][dynamic]Field_Chunk_Cache_Entry,
	count:   int,
}

field_chunk_cache: Field_Chunk_Cache

// What the cache holds for a key: the chunk (Cached), an entry another
// test claimed and is generating (Claimed_Elsewhere), or nothing, which
// is claimed for the caller while the cache has room (Claimed, the caller
// fills it) and left alone when it is full (Full).
Field_Chunk_Cache_Lookup :: enum {
	Cached,
	Claimed,
	Claimed_Elsewhere,
	Full,
}

// The inputs stage_generated_field_set passes to generate_field_chunk;
// borrows the planet's springs.
field_chunk_cache_key :: proc(state: ^Simulation_State, coordinate: Field_Chunk_Coordinate, crater_overlay: bool) -> Field_Chunk_Cache_Key {
	return {state.world.settings.seed, state.field.spacing_millimetres, planet_generation_record(state.world.planet), crater_overlay, coordinate}
}

// The springs by content, the rest of the records byte for byte (== does
// not compile on a struct holding a slice). Equal bytes are equal fields,
// so this can only miss, never hand out a wrong chunk. A slice added to
// the record would compare by address and miss across sessions, or match
// a freed session's reused address: clone it in look_up_field_chunk_cache
// and compare it by content here, as the springs.
field_chunk_cache_keys_equal :: proc(first, second: Field_Chunk_Cache_Key) -> bool {
	first_record, second_record := first.record, second.record
	first_record.springs, second_record.springs = nil, nil
	return first.seed == second.seed && first.spacing_millimetres == second.spacing_millimetres && first.crater_overlay == second.crater_overlay && first.coordinate == second.coordinate && slice.equal(first.record.springs, second.record.springs) && runtime.memory_equal(&first_record, &second_record, size_of(Planet_Generation_Record))
}

// The entry of the key, nil when the cache has none. Under the lock, the
// pointer used only under it: a later append may move the bucket.
find_field_chunk_cache_entry :: proc(key: Field_Chunk_Cache_Key) -> ^Field_Chunk_Cache_Entry {
	bucket := field_chunk_cache.entries[key.coordinate]
	for &entry in bucket {
		if field_chunk_cache_keys_equal(entry.key, key) {
			return &entry
		}
	}
	return nil
}

look_up_field_chunk_cache :: proc(key: Field_Chunk_Cache_Key) -> (cached: ^Field_Chunk, lookup: Field_Chunk_Cache_Lookup) {
	sync.mutex_lock(&field_chunk_cache.mutex)
	defer sync.mutex_unlock(&field_chunk_cache.mutex)
	if entry := find_field_chunk_cache_entry(key); entry != nil {
		return entry.chunk, entry.chunk != nil ? .Cached : .Claimed_Elsewhere
	}
	if field_chunk_cache.count >= FIELD_CHUNK_CACHE_CAPACITY {
		return nil, .Full
	}
	heap := runtime.heap_allocator()
	if field_chunk_cache.entries == nil {
		field_chunk_cache.entries = make(map[Field_Chunk_Coordinate][dynamic]Field_Chunk_Cache_Entry, heap)
	}
	bucket := field_chunk_cache.entries[key.coordinate]
	if bucket == nil {
		bucket = make([dynamic]Field_Chunk_Cache_Entry, heap)
	}
	owned := key
	owned.record.springs = slice.clone(key.record.springs, heap)
	append(&bucket, Field_Chunk_Cache_Entry{key = owned})
	field_chunk_cache.entries[key.coordinate] = bucket
	field_chunk_cache.count += 1
	return nil, .Claimed
}

// A heap copy of the generated chunk, made outside the lock, fills the
// claimed entry.
fill_field_chunk_cache :: proc(key: Field_Chunk_Cache_Key, chunk: ^Field_Chunk) {
	heap := runtime.heap_allocator()
	copied := new(Field_Chunk, heap)
	copied^ = chunk^
	copied.crater_overlay = copy_field_crater_overlay(chunk.crater_overlay, heap)
	sync.mutex_lock(&field_chunk_cache.mutex)
	defer sync.mutex_unlock(&field_chunk_cache.mutex)
	find_field_chunk_cache_entry(key).chunk = copied
}

// Nil for nil: dig_impact_crater skips a chunk whose overlay is nil and
// counts the others.
copy_field_crater_overlay :: proc(overlay: [dynamic]Field_Crater_Sample, allocator: runtime.Allocator) -> [dynamic]Field_Crater_Sample {
	if overlay == nil {
		return nil
	}
	copied := make([dynamic]Field_Crater_Sample, 0, len(overlay), allocator)
	append(&copied, ..overlay[:])
	return copied
}

// The cached chunk copied into chunk, its overlay in context.allocator
// (the session frees it with the chunk). No lock: an entry's chunk is
// never written or freed once set.
copy_cached_field_chunk :: proc(cached: ^Field_Chunk, chunk: ^Field_Chunk) {
	chunk^ = cached^
	chunk.crater_overlay = copy_field_crater_overlay(cached.crater_overlay, context.allocator)
}

// generate_field_chunk through the cache, chunk zeroed as new leaves it: a
// copy of the cached chunk, or the chunk generated (and cached when the
// caller claimed it). False, with chunk untouched, when defer_claimed is
// set and another test is generating it. It takes the state, not a
// planet, so only a session's planet reaches the cache; a test with a
// hand-built planet calls generate_field_chunk.
generate_cached_field_chunk :: proc(state: ^Simulation_State, coordinate: Field_Chunk_Coordinate, chunk: ^Field_Chunk, crater_overlay := false, defer_claimed := false) -> (generated: bool) {
	key := field_chunk_cache_key(state, coordinate, crater_overlay)
	cached, lookup := look_up_field_chunk_cache(key)
	if lookup == .Cached {
		copy_cached_field_chunk(cached, chunk)
		return true
	}
	if lookup == .Claimed_Elsewhere && defer_claimed {
		return false
	}
	generate_field_chunk(state.world.settings.seed, state.world.planet, state.field.spacing_millimetres, coordinate, chunk, crater_overlay)
	if lookup == .Claimed {
		fill_field_chunk_cache(key, chunk)
	}
	return true
}

// stage_generated_field_set through the cache. The chunks another test is
// generating are left to the end, each then a copy when its claimer has
// filled it and generated here otherwise, so tests starting together
// share the generation of one set instead of each generating it. A
// claimer that never fills (a test that crashed in generate_field_chunk)
// leaves its entry claimed; nothing waits on it.
stage_cached_field_set :: proc(state: ^Simulation_State) {
	field := &state.field
	deferred := make([dynamic]Field_Chunk_Coordinate, context.temp_allocator)
	for coordinate in needed_field_chunks(state) {
		if coordinate in field.world.chunks || coordinate in field.arrived_chunks {
			continue
		}
		chunk := new(Field_Chunk)
		if generate_cached_field_chunk(state, coordinate, chunk, crater_overlay = true, defer_claimed = true) {
			stage_field_chunk_arrival(field, chunk)
		} else {
			free(chunk)
			append(&deferred, coordinate)
		}
	}
	for coordinate in deferred {
		chunk := new(Field_Chunk)
		generate_cached_field_chunk(state, coordinate, chunk, crater_overlay = true)
		stage_field_chunk_arrival(field, chunk)
	}
}

// Every field of the two chunks is the same, the overlays sample for
// sample.
field_chunks_equal :: proc(first, second: ^Field_Chunk) -> bool {
	return first.coordinate == second.coordinate && first.density == second.density && first.material == second.material && first.tint == second.tint && first.water == second.water && first.water_still == second.water_still && first.water_flow == second.water_flow && first.water_moved == second.water_moved && first.water_awake == second.water_awake && first.water_source == second.water_source && first.water_owner == second.water_owner && first.water_pressure_failed == second.water_pressure_failed && first.block_light == second.block_light && first.sky_light == second.sky_light && first.dirty == second.dirty && first.wave_dirty == second.wave_dirty && first.wave_dirty_tick == second.wave_dirty_tick && first.modified == second.modified && first.hash_current == second.hash_current && first.state_hash == second.state_hash && first.generated_shade == second.generated_shade && slice.equal(first.crater_overlay[:], second.crater_overlay[:])
}

// The chunk generate_field_chunk makes for the state at the coordinate,
// expected equal to the cache's before and after it holds it; the caller
// destroys it.
expect_cached_field_chunk_is_generated :: proc(t: ^testing.T, state: ^Simulation_State, coordinate: Field_Chunk_Coordinate, crater_overlay: bool, label: string) -> ^Field_Chunk {
	generated := new(Field_Chunk)
	generate_field_chunk(state.world.settings.seed, state.world.planet, state.field.spacing_millimetres, coordinate, generated, crater_overlay)
	for pass in 0 ..< 2 {
		cached := new(Field_Chunk)
		defer destroy_field_chunk(cached)
		generate_cached_field_chunk(state, coordinate, cached, crater_overlay)
		testing.expectf(t, field_chunks_equal(generated, cached), "%s, pass %d: the cached chunk is not the generated one", label, pass)
	}
	return generated
}

// Work item 0318: the cache hands out the chunk generate_field_chunk
// makes, before and after it holds it, for a session's home chunk and
// for a change of each part of its key alone (each a chunk of its own),
// so a key that left a part out would hand out the first chunk. A second
// session of the same planet and seed finds the chunk the first filled
// (the larger radius's, a key no other test fills, so the first session
// claimed and filled it): a record field that defeated the key's
// comparison would miss there instead of silently slowing the suite (the
// main agent's decision 3).
@(test) // slow
test_the_cached_field_chunks_are_the_generated_ones :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	defer end_session(session)
	state := &session.simulation
	spacing := state.field.spacing_millimetres
	home := sample_to_field_chunk_coordinate(world_position_to_sample(state.players[0].field.position, spacing))
	base := expect_cached_field_chunk_is_generated(t, state, home, true, "the home")
	defer destroy_field_chunk(base)
	differs :: proc(t: ^testing.T, base, changed: ^Field_Chunk, label: string) {
		testing.expectf(t, !field_chunks_equal(base, changed), "%s: the same chunk", label)
		destroy_field_chunk(changed)
	}
	differs(t, base, expect_cached_field_chunk_is_generated(t, state, home, false, "no overlay"), "no overlay")
	state.world.planet.crater_at_impact = false
	differs(t, base, expect_cached_field_chunk_is_generated(t, state, home, true, "baked"), "baked")
	state.world.planet.crater_at_impact = true
	state.world.settings.seed += 1
	differs(t, base, expect_cached_field_chunk_is_generated(t, state, home, true, "another seed"), "another seed")
	state.world.settings.seed -= 1
	state.field.spacing_millimetres = 500
	differs(t, base, expect_cached_field_chunk_is_generated(t, state, home, true, "500 mm"), "500 mm")
	state.field.spacing_millimetres = spacing
	state.world.planet.radius_metres += 1000
	differs(t, base, expect_cached_field_chunk_is_generated(t, state, home, true, "a larger radius"), "a larger radius")
	state.world.planet.radius_metres -= 1000

	second := start_field_test_session(config, content)
	defer end_session(second)
	second.simulation.world.planet.radius_metres += 1000
	_, lookup := look_up_field_chunk_cache(field_chunk_cache_key(&second.simulation, home, true))
	testing.expect_value(t, lookup, Field_Chunk_Cache_Lookup.Cached)

	planet := state.world.planet
	testing.expect(t, len(planet.springs) > 0, "the shipped planet has springs")
	if len(planet.springs) == 0 {
		return
	}
	spring_sample, found := planet_spring_sample(make_planet_generation(state.world.settings.seed, planet, spacing), planet.springs[0])
	testing.expect(t, found, "the first spring has a sample")
	spring := sample_to_field_chunk_coordinate(spring_sample)
	wet := expect_cached_field_chunk_is_generated(t, state, spring, true, "the spring's chunk")
	defer destroy_field_chunk(wet)
	springs := state.world.planet.springs
	state.world.planet.springs = nil
	differs(t, wet, expect_cached_field_chunk_is_generated(t, state, spring, true, "no springs"), "no springs")
	state.world.planet.springs = springs
}

// Work item 0318: the cached staging stages the chunks the game's
// stage_generated_field_set stages, each the same.
@(test)
test_the_cached_field_set_stages_as_the_generated_one :: proc(t: ^testing.T) {
	config := test_field_game_config()
	config.field_simulation.chunk_radius = 0
	config.field_simulation.chunk_margin = 0
	content := make_field_test_game_content()
	generated := start_field_test_session(config, content)
	defer end_session(generated)
	cached := start_field_test_session(config, content)
	defer end_session(cached)
	stage_generated_field_set(&generated.simulation)
	stage_cached_field_set(&cached.simulation)
	stage_cached_field_set(&cached.simulation)
	first, second := &generated.simulation.field.arrived_chunks, &cached.simulation.field.arrived_chunks
	testing.expect(t, len(first) > 0, "the set stages chunks")
	testing.expect_value(t, len(second), len(first))
	for coordinate, chunk in first {
		other, found := second[coordinate]
		testing.expectf(t, found && field_chunks_equal(chunk, other), "the chunk %v differs", coordinate)
	}
}
