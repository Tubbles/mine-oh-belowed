#+build !windows
package platform

import "core:time/timezone"

// The tz database's "local" region (/etc/localtime or TZ).
load_local_zone :: proc() -> Local_Zone {
	region, _ := timezone.region_load("local")
	return Local_Zone{region = region}
}

destroy_local_zone :: proc(zone: ^Local_Zone) {
	timezone.region_destroy(zone.region)
	zone.region = nil
}
