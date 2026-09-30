#+build windows
package platform

import "core:sys/windows"

// The Windows side of local_zone.odin (work item 0102): the current
// offset from GetTimeZoneInformation, which Wine serves from the host's
// zone, rather than core:time/timezone's region, whose Windows path calls
// ICU and aborts under Wine. Windows gives the bias in minutes to add to
// local time to reach UTC, plus the standard or daylight bias for the
// part of the year in force, so the offset is their negative.

foreign import kernel32 "system:Kernel32.lib"

@(default_calling_convention = "system")
foreign kernel32 {
	GetTimeZoneInformation :: proc(information: ^windows.TIME_ZONE_INFORMATION) -> windows.DWORD ---
}

TIME_ZONE_ID_INVALID :: 0xFFFFFFFF
TIME_ZONE_ID_DAYLIGHT :: 2

load_local_zone :: proc() -> Local_Zone {
	information: windows.TIME_ZONE_INFORMATION
	id := GetTimeZoneInformation(&information)
	if id == TIME_ZONE_ID_INVALID {
		return {}
	}
	return Local_Zone{offset_seconds = local_zone_offset_seconds(i64(information.Bias), i64(information.StandardBias), i64(information.DaylightBias), id == TIME_ZONE_ID_DAYLIGHT)}
}

destroy_local_zone :: proc(zone: ^Local_Zone) {}
