package game

// Used when no --seed is given, so that runs are reproducible.
DEFAULT_WORLD_SEED :: u64(20260927)

// One sub seed per purpose, so no noise field or hash stream is shared
// between two uses of the world seed.
Generation_Purpose :: enum u8 {
	Continental_Height,
	Hill_Height,
	Detail_Height,
	Rivers,
	Moisture,
	Caves,
	Topsoil,
	Trees,
	Boulders,
	Veins,
	// Appended last (work items 0035, 0036 and 0045), so adding them left
	// the other seeds unchanged.
	Deep_Veins,
	Cave_Crates,
	Starter_Veins,
}

Purpose_Seeds :: [Generation_Purpose]u64

hash_combine :: proc(seed: u64, value: u64) -> u64 {
	return hash_u64(seed ~ hash_u64(value))
}

derive_purpose_seeds :: proc(world_seed: u64) -> Purpose_Seeds {
	seeds: Purpose_Seeds
	for purpose in Generation_Purpose {
		seeds[purpose] = hash_combine(world_seed, u64(purpose) + 1)
	}
	return seeds
}

pack_pair :: proc(first, second: i32) -> u64 {
	return u64(u32(first)) << 32 | u64(u32(second))
}

hash_column :: proc(seed: u64, x, z: i32) -> u64 {
	return hash_combine(seed, pack_pair(x, z))
}

// Uniform in [0, 1), from the top 53 bits.
hash_to_unit :: proc(hash: u64) -> f64 {
	return f64(hash >> 11) / f64(u64(1) << 53)
}

// Uniform in minimum to maximum inclusive. The modulo bias is irrelevant for
// the small ranges used here.
hash_to_range :: proc(hash: u64, minimum, maximum: i64) -> i64 {
	return minimum + i64(hash % u64(maximum - minimum + 1))
}
