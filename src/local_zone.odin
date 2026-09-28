package game

import "core:time/datetime"
import "core:time/timezone"

// The player's local time zone for the dates the title screen shows
// (date_text in save_list.odin). Loaded per platform: load_local_zone in
// local_zone_posix.odin reads the tz database's "local" region, and
// local_zone_windows.odin asks Windows for the current offset instead,
// since core:time/timezone's Windows path asks ICU for the zone's name
// (ucal_getDefaultTimeZone), which Wine does not implement and aborts on
// (work item 0102, seen under Proton 11). One of the two fields is in
// use: the region when one loaded, else the offset, 0 for UTC.
Local_Zone :: struct {
	region:         ^datetime.TZ_Region,
	offset_seconds: i64,
}

// utc in the zone: through the region, else shifted by the offset.
to_local_datetime :: proc(utc: datetime.DateTime, zone: Local_Zone) -> datetime.DateTime {
	if zone.region != nil {
		return timezone.datetime_to_tz(utc, zone.region) or_else utc
	}
	local, error := datetime.add(utc, datetime.Delta{seconds = zone.offset_seconds})
	return error == .None ? local : utc
}

// Windows' TIME_ZONE_INFORMATION to an offset east of UTC in seconds: the
// biases are minutes to add to local time to reach UTC, the daylight one
// while daylight time is in force, the standard one otherwise.
local_zone_offset_seconds :: proc(bias_minutes, standard_bias_minutes, daylight_bias_minutes: i64, daylight: bool) -> i64 {
	return -(bias_minutes + (daylight ? daylight_bias_minutes : standard_bias_minutes)) * 60
}
