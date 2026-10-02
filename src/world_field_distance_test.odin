package game

import "core:testing"

// The probe reads the distance to a flat surface and its normal; a slope
// of 30 degrees gives its normal tilted, within the 1/128 sample of the
// density byte (about 1.5 degrees here).
@(test)
test_the_field_probe_reads_distance_and_normal :: proc(t: ^testing.T) {
	world := make_test_field(Test_Terrain{kind = .Flat}, 1000)
	defer destroy_field_world(&world)
	probe := field_surface_probe(&world, 1000, test_site_point(0, POSITION_UNITS_PER_METRE / 2, 0))
	testing.expectf(t, abs(probe.distance - POSITION_UNITS_PER_METRE / 2) <= POSITION_UNITS_PER_METRE / 64, "distance %d", probe.distance)
	slope := make_test_field(Test_Terrain{kind = .Slope, slope_degrees = 30}, 1000)
	defer destroy_field_world(&slope)
	normal := field_surface_probe(&slope, 1000, test_site_point(0, POSITION_UNITS_PER_METRE / 4, 0)).normal
	cosine := normal.y
	testing.expectf(t, abs(cosine - fixed_cosine(degrees_to_angle_units(30))) < UNIT_VECTOR_ONE / 20, "normal %v", normal)
}

// From three spacings above flat ground to three inside it, in steps of
// an eighth of a spacing, the probe reads the height within a tenth of a
// sample at every spacing, saturated band included.
@(test)
test_the_field_probe_reads_the_exact_distance_across_the_band :: proc(t: ^testing.T) {
	for spacing_millimetres in TEST_FIELD_SPACINGS {
		world := make_test_field(Test_Terrain{kind = .Flat}, spacing_millimetres)
		defer destroy_field_world(&world)
		spacing := sample_axis_to_position(1, spacing_millimetres)
		for height := -3 * spacing; height <= 3 * spacing; height += spacing / 8 {
			probe := field_surface_probe(&world, spacing_millimetres, test_site_point(spacing / 3, height, 0))
			testing.expectf(t, probe.found && abs(probe.distance - height) <= spacing / 10, "%d mm: at %d the probe read %d", spacing_millimetres, height, probe.distance)
			testing.expectf(t, probe.normal.y > UNIT_VECTOR_ONE * 99 / 100, "%d mm: at %d the normal is %v", spacing_millimetres, height, probe.normal)
		}
		far := field_surface_probe(&world, spacing_millimetres, test_site_point(0, 5 * spacing, 0))
		testing.expect(t, !far.found && far.distance > 3 * spacing, "five spacings out finds no surface")
	}
}
