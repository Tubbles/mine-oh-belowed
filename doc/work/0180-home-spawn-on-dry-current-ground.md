# 0180: The home spawn on dry, current ground

Status: todo (M13 follow up, from the switch of 0179; before or with the M14 items)

## Goal

Every new or joining player lands at the home on ground that is dry and standable, for every seed and however the home has been dug or built since the world began. Today `field_home_player` (`simulation_field.odin`) stands the player on the generated surface at the record's home whatever its height (only the default seed was measured dry, `doc/log/2026-10-03.md`), the spawn ignores a pit dug or a pad laid at the site, the spawn's pad pitch comes from the current data while the pod's frame keeps its saved pitch, and a home of latitude 0, longitude 0 reads as no home (`planet_home_direction`).

## Change

- Generation picks the home: from the record's point, the nearest surface sample above the sea level along a deterministic outward search on the sphere (the same on every machine), so a seed whose home point lies under the sea still starts dry; the chosen point is what the world file records.
- The planet record carries whether a home is set (a flag or the loader refusing 0/0), so no real point reads as absent.
- The spawn site is the home and the pod's forward as today, but the feet stand on the current ground there: the field as edited plus the frame table (`field_ground_under` over the loaded set), so a pit puts the player at its bottom and a pad on top of it; the pad distance uses the pod frame's saved pitch.
- `doc/architecture.md` (the spawn), `doc/content.md` (the home record) updated.

## Verify

- The build and check commands of 0168.
- Tests: a seed whose home point lies under the sea spawns on dry ground within a bounded distance; a home of 0/0 is a home; a pit dug at the spawn site puts a joining player at its bottom and a foundation laid there puts the joiner on it; two machines compute the same spawn from the same save.
