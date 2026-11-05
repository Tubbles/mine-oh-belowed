# 0295: Water tools and pumps

Status: todo (2026-11-05)

Milestone: the water tech demo (0291); the water stream after 0294.

## Goal

The demo kit's water bucket pours water where the player aims, the drain bucket takes it away, and a pump placed on the ground or in a lake runs as a sink or a source at an honest rate, toggled by the player, lowering or raising the lake with the litres shown. With the `bodies` model a pump draws from the body under its intake; with `teleport` from the samples under it.

## Controls

- Water bucket held: Place (L2) pours `bucket_fill_per_press` into the aimed air sample and the room around it (the brush's size, Next_Brush Y cycles the brush as for the ground), woken; a hold pours every `bucket_repeat_ticks`. Mine (R2) with the water bucket held does nothing.
- Drain bucket held: Place (L2) removes up to `bucket_fill_per_press` from the aimed water samples (the brush), the litres credited to the HUD counter; hold repeats.
- Pump held: Place (L2) places a pump standing on the aimed ground (the bare ground placement of `entity_frames.odin` with the flatness check relaxed to a sample in the demo), its intake the lowest air sample under its footprint, its outlet a sample above its top; Mine (R2) aimed at a pump picks it up.
- Interact (X) aimed at a pump toggles it: Sink (takes `pump_rate_litres_per_second` from the intake) to Source (adds the same at the outlet) to Off. The pump's panel line on the HUD names the state and the litres moved. No new bindings.

## Change

- Items `water_bucket`, `drain_bucket` (tool roles in `data/items.sjson`, `field_tool_for_item` maps them to `Field_Held_Tool.Water` and `.Drain`), `field_player_edit` builds a `Field_Water_Edit` queued with the brush edits and drained in `finish_field_tick` before `step_field_water` through `set_field_water` and `wake_field_water_around`; pours displace into room only (never into ground), drains take what is there.
- Machine `water_pump` in `data/machines.sjson` (kind `water_pump`, footprint 1 by 1 by 1 on the field, a model from the kit's pump primitive, no power in the demo), `Water_Pump` entity with `mode` (Off, Sink, Source), `litres`, intake and outlet samples; `tick_water_pumps` in `finish_field_tick` before the water step: Sink subtracts per tick with the rate's credit (`take_power_step` pattern) from the intake sample's column, or with `bodies` from the body under the intake (0293's `body_take_volume`), Source adds at the outlet into room, both counted; an intake over no water idles and the HUD line says "intake dry".
- `fluid_network.odin` untouched in this item (the offshore pump's coupling to bodies is 0294 of the plan's numbering and stays a later item).
- Docs: `doc/content.md` (the items and the machine), `doc/input.md` (the tools' controls), the log.

## Verify

- The checks and the suite.
- Tests: a pour of N presses raises a basin's total by N times the press fill; a drain lowers it by what it takes; a pump as Sink on a 20-sample lake for 600 ticks removes rate times 10 s within one press fill and the level falls accordingly (both models); Source refills it; a pump over dry ground moves nothing and reports dry; a pump picked up returns its item; determinism: two worlds with a running pump hash alike.
