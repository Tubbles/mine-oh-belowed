package game

import "core:testing"

@(test)
test_format_per_minute :: proc(t: ^testing.T) {
	testing.expect_value(t, format_per_minute(0), "0.0/min")
	testing.expect_value(t, format_per_minute(7.5), "7.5/min")
	testing.expect_value(t, format_per_minute(0.04), "0.0/min")
	testing.expect_value(t, format_per_minute(-0.04), "0.0/min")
	testing.expect_value(t, format_per_minute(1234.56), "1234.6/min")
}

@(test)
test_format_power_boundaries :: proc(t: ^testing.T) {
	testing.expect_value(t, format_power(0), "0.0 kW")
	testing.expect_value(t, format_power(999.94), "999.9 kW")
	testing.expect_value(t, format_power(999.96), "1.0 MW")
	testing.expect_value(t, format_power(1000), "1.0 MW")
	testing.expect_value(t, format_power(1500), "1.5 MW")
	testing.expect_value(t, format_power(12345.6), "12.3 MW")
}

@(test)
test_format_volume_boundaries :: proc(t: ^testing.T) {
	testing.expect_value(t, format_volume(0), "0 L")
	testing.expect_value(t, format_volume(999.4), "999 L")
	testing.expect_value(t, format_volume(999.5), "1.0 kL")
	testing.expect_value(t, format_volume(1000), "1.0 kL")
	testing.expect_value(t, format_volume(999_940), "999.9 kL")
	testing.expect_value(t, format_volume(999_960), "1.0 ML")
	testing.expect_value(t, format_volume(2_500_000), "2.5 ML")
}

@(test)
test_format_blocks :: proc(t: ^testing.T) {
	table, _ := parse_string_table(transmute([]byte)string(`unit_block = "block", unit_blocks = "blocks"`))
	defer destroy_string_table(&table)
	testing.expect_value(t, format_blocks_with(&table, 0), "0 blocks")
	testing.expect_value(t, format_blocks_with(&table, 1), "1 block")
	testing.expect_value(t, format_blocks_with(&table, 2), "2 blocks")
	testing.expect_value(t, format_blocks_with(&table, 1_000_000), "1000000 blocks")
}
