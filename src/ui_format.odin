package game

import "core:fmt"
import "core:math"

// One formatter per unit, so every screen shows quantities the same way.
// Unit symbols (kW, L, /min) are SI style and stay literal; words come from
// the string table. Results live in the temp allocator.

UNIT_STEP :: 1000

// Zero comes back positive, so tiny negatives do not print as -0.0.
round_to_tenth :: proc(value: f32) -> f32 {
	rounded := math.round(value * 10) / 10
	return rounded == 0 ? 0 : rounded
}

round_to_whole :: proc(value: f32) -> f32 {
	rounded := math.round(value)
	return rounded == 0 ? 0 : rounded
}

format_per_minute :: proc(items_per_minute: f32) -> string {
	return fmt.tprintf("%.1f/min", round_to_tenth(items_per_minute))
}

// kW below 1000, MW from there, one decimal. The unit switches on the
// rounded value, so 999.96 kW reads 1.0 MW rather than 1000.0 kW.
format_power :: proc(kilowatts: f32) -> string {
	if abs(round_to_tenth(kilowatts)) < UNIT_STEP {
		return fmt.tprintf("%.1f kW", round_to_tenth(kilowatts))
	}
	return fmt.tprintf("%.1f MW", round_to_tenth(kilowatts / UNIT_STEP))
}

// Whole litres below 1000, then kL and ML with one decimal.
format_volume :: proc(litres: f32) -> string {
	if abs(round_to_whole(litres)) < UNIT_STEP {
		return fmt.tprintf("%.0f L", round_to_whole(litres))
	}
	kilolitres := litres / UNIT_STEP
	if abs(round_to_tenth(kilolitres)) < UNIT_STEP {
		return fmt.tprintf("%.1f kL", round_to_tenth(kilolitres))
	}
	return fmt.tprintf("%.1f ML", round_to_tenth(kilolitres / UNIT_STEP))
}

// A per tick flow in litres, as volume per minute.
format_litres_per_minute :: proc(litres_per_tick: i32, tick_rate: int) -> string {
	return fmt.tprintf("%s/min", format_volume(f32(litres_per_tick) * f32(tick_rate) * 60))
}

format_blocks_with :: proc(table: ^String_Table, count: int) -> string {
	word := lookup_text(table, count == 1 ? "unit_block" : "unit_blocks")
	return fmt.tprintf("%d %s", count, word)
}

format_blocks :: proc(count: int) -> string {
	return format_blocks_with(&global_string_table, count)
}
