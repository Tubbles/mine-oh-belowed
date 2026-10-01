package game

// Labs and the research queue (doc/fluids.md, Assembler, lab and
// research). The simulation holds one queued technology and its progress
// in units. A lab with power and one of each of the technology's science
// packs takes a pack set, works the technology's time per unit at its
// speed with the power credit (power_machine.odin), and adds one unit to
// the shared progress. Labs start a unit only while the units done plus
// those in progress are short of the cost, so several labs never overshoot.
// When the units reach the cost the technology is finished; the
// simulation marks it researched after the entity tick (simulation_tick),
// since the unlocks live outside the world.
//
// Queueing another technology keeps the units done of the old one and
// resumes the new one where it was left, as Factorio does. It bumps
// serial, so a unit in progress for the old queue is dropped with its
// packs.
//
// Infinite technologies (work item 0041) count levels in levels: a
// finished level adds one and empties the queue like any other finished
// research (user decision 2026-09-27), the next level costing more
// (technology_level_cost). Every level of research_speed
// makes every lab faster by its effect percent.

MAXIMUM_LAB_SLOTS :: 8

Lab_State :: enum u8 {
	No_Research,
	No_Packs,
	No_Power,
	Researching,
}

@(rodata)
lab_state_keys := [Lab_State]string {
	.No_Research = "machine_state_no_research",
	.No_Packs    = "machine_state_no_packs",
	.No_Power    = "machine_state_unpowered",
	.Researching = "machine_state_researching",
}

// Slot index i holds Machine_Registry.lab_packs[i]. serial is the queue's
// serial the unit in progress belongs to.
Lab :: struct {
	using common:   Entity_Common,
	slot_count:     int,
	slots:          [MAXIMUM_LAB_SLOTS]Item_Stack,
	working:        bool,
	serial:         u32,
	progress_ticks: u32,
	state:          Lab_State,
	power:          Power_State,
}

// finished is set on the tick a technology completes, until the
// simulation applies it. units_done is the queued technology's progress;
// units_kept holds every other technology's, indexed by technology.
// levels counts the finished levels of every infinite technology, indexed
// by technology.
Research_State :: struct {
	queued:              bool,
	technology:          int,
	units_done:          int,
	units_kept:          [MAXIMUM_TECHNOLOGIES]int,
	serial:              u32,
	finished:            bool,
	finished_technology: int,
	levels:              [MAXIMUM_TECHNOLOGIES]u32,
}

make_lab :: proc(common: Entity_Common, slot_count: int) -> Lab {
	lab := Lab {
		common     = common,
		slot_count = min(slot_count, MAXIMUM_LAB_SLOTS),
	}
	for &slot in lab.slots {
		slot = EMPTY_STACK
	}
	return lab
}

Technology_Status :: enum u8 {
	Researched,
	Available,
	// A prerequisite is not researched yet.
	Locked,
}

// A placeholder opens recipes that do not exist yet, and a quest gate
// waits for its main quest, so both stay locked. An infinite technology is
// never done.
technology_status :: proc(technologies: Technology_Registry, unlocks: Recipe_Unlocks, technology: int) -> Technology_Status {
	if unlocks.researched[technology] && !technologies.technologies[technology].infinite {
		return .Researched
	}
	if technologies.technologies[technology].placeholder || technologies.technologies[technology].quest_gate {
		return .Locked
	}
	for prerequisite in technologies.technologies[technology].prerequisites {
		if !unlocks.researched[prerequisite] {
			return .Locked
		}
	}
	return .Available
}

Research_Refusal :: enum u8 {
	None,
	Researched,
	Locked,
	Placeholder,
	Quest_Gate,
}

@(rodata)
research_refusal_keys := [Research_Refusal]string {
	.None        = "",
	.Researched  = "research_refused_researched",
	.Locked      = "research_refused_locked",
	.Placeholder = "research_refused_placeholder",
	.Quest_Gate  = "research_refused_quest_gate",
}

research_refusal :: proc(technologies: Technology_Registry, unlocks: Recipe_Unlocks, technology: int) -> Research_Refusal {
	switch technology_status(technologies, unlocks, technology) {
	case .Researched:
		return .Researched
	case .Locked:
		switch {
		case technologies.technologies[technology].placeholder:
			return .Placeholder
		case technologies.technologies[technology].quest_gate:
			return .Quest_Gate
		}
		return .Locked
	case .Available:
	}
	return .None
}

// Replaces the queued technology with an available one, resuming its
// kept progress. Queueing the queued technology again changes nothing.
queue_research :: proc(research: ^Research_State, technologies: Technology_Registry, unlocks: Recipe_Unlocks, technology: int) -> Research_Refusal {
	if refusal := research_refusal(technologies, unlocks, technology); refusal != .None {
		return refusal
	}
	if research.queued && research.technology == technology {
		return .None
	}
	if research.queued {
		research.units_kept[research.technology] = research.units_done
	}
	research.queued, research.technology = true, technology
	research.units_done = research.units_kept[technology]
	research.serial += 1
	return .None
}

// The slot of a pack item, or -1.
lab_slot_of :: proc(lab_packs: []Item_Id, item: Item_Id) -> int {
	for pack, index in lab_packs {
		if pack == item {
			return index
		}
	}
	return -1
}

lab_has_packs :: proc(lab: Lab, technology: Technology, lab_packs: []Item_Id) -> bool {
	for pack in technology.science_packs {
		slot := lab_slot_of(lab_packs, pack)
		if slot < 0 || slot >= lab.slot_count || stack_is_empty(lab.slots[slot]) {
			return false
		}
	}
	return true
}

take_pack_set :: proc(lab: ^Lab, technology: Technology, lab_packs: []Item_Id) {
	for pack in technology.science_packs {
		take_from_slot(&lab.slots[lab_slot_of(lab_packs, pack)], 1)
	}
}

// The units the queued technology takes: its cost, or the next level's.
queued_research_cost :: proc(research: Research_State, technologies: Technology_Registry) -> int {
	return technology_next_cost(technologies.technologies[research.technology], research.levels, research.technology)
}

// A lab's speed with the research speed levels: the speed times one plus
// the effect, in integer per mille.
boosted_speed_percent :: proc(speed_percent, bonus_per_mille: u32) -> u32 {
	return u32(u64(speed_percent) * u64(1000 + bonus_per_mille) / 1000)
}

lab_speed_percent :: proc(machine: Machine, research: Research_State, technologies: Technology_Registry) -> u32 {
	return boosted_speed_percent(machine.speed_percent, technology_effect_per_mille(technologies, research.levels, .Research_Speed))
}

// Ticks per unit at the lab's speed, at least one, like recipe_ticks.
technology_unit_ticks :: proc(technology: Technology, speed_percent: u32, tick_rate: int) -> u32 {
	ticks := u64(technology.milliseconds_per_pack) * u64(tick_rate) * 100 / (1000 * u64(max(speed_percent, 1)))
	return max(u32(ticks), 1)
}

lab_unit_is_current :: proc(lab: Lab, research: Research_State) -> bool {
	return lab.working && research.queued && lab.serial == research.serial
}

lab_wants_power :: proc(lab: Lab, research: Research_State, technologies: Technology_Registry, lab_packs: []Item_Id) -> bool {
	if lab_unit_is_current(lab, research) {
		return true
	}
	return research.queued && lab_has_packs(lab, technologies.technologies[research.technology], lab_packs)
}

// Units in progress for the current queue, over every lab.
units_in_progress :: proc(labs: []Lab, research: Research_State) -> int {
	count := 0
	for lab in labs {
		if lab.alive && lab_unit_is_current(lab, research) {
			count += 1
		}
	}
	return count
}

// Why the lab cannot start a unit, or blocked false.
lab_start_state :: proc(lab: Lab, research: Research_State, technologies: Technology_Registry, lab_packs: []Item_Id, in_progress: int) -> (state: Lab_State, blocked: bool) {
	if !research.queued {
		return .No_Research, true
	}
	technology := technologies.technologies[research.technology]
	switch {
	case research.units_done + in_progress >= queued_research_cost(research, technologies):
		return .No_Research, true
	case !lab_has_packs(lab, technology, lab_packs):
		return .No_Packs, true
	}
	return .Researching, false
}

// An infinite technology gains a level; the queue empties either way.
finish_research_unit :: proc(research: ^Research_State, technologies: Technology_Registry) {
	research.units_done += 1
	if research.units_done < queued_research_cost(research^, technologies) {
		return
	}
	research.finished, research.finished_technology = true, research.technology
	research.units_kept[research.technology] = 0
	research.units_done = 0
	if technologies.technologies[research.technology].infinite {
		research.levels[research.technology] += 1
	}
	research.queued = false
}

// One tick of a lab. in_progress counts the units under way in every lab
// for the current queue and is kept up to date as units start and end.
advance_lab :: proc(lab: ^Lab, machine: Machine, research: ^Research_State, in_progress: ^int, technologies: Technology_Registry, lab_packs: []Item_Id, tick_rate: int) {
	if lab.working && !lab_unit_is_current(lab^, research^) {
		lab.working, lab.progress_ticks = false, 0
	}
	if !lab.working {
		state, blocked := lab_start_state(lab^, research^, technologies, lab_packs, in_progress^)
		if blocked {
			lab.state = state
			return
		}
	}
	if !power_is_on(lab.power) {
		lab.state = .No_Power
		return
	}
	technology := technologies.technologies[research.technology]
	if !lab.working {
		take_pack_set(lab, technology, lab_packs)
		lab.working, lab.serial, lab.progress_ticks = true, research.serial, 0
		in_progress^ += 1
	}
	lab.state = .Researching
	if take_power_step(&lab.power) {
		lab.progress_ticks += 1
	}
	if lab.progress_ticks < technology_unit_ticks(technology, lab_speed_percent(machine, research^, technologies), tick_rate) {
		return
	}
	lab.working, lab.progress_ticks = false, 0
	in_progress^ -= 1
	finish_research_unit(research, technologies)
}

tick_labs :: proc(world: ^World, records: ^Game_Records, content: Simulation_Content, tick_rate: int) {
	labs := world.entities.labs.entries[:]
	in_progress := units_in_progress(labs, records.research)
	for &lab in labs {
		if lab.alive {
			machine := content.machines.machines[lab.machine]
			before := lab
			advance_lab(&lab, machine, &records.research, &in_progress, content.technologies, content.machines.lab_packs, tick_rate)
			record_slot_consumption(&records.statistics, before.slots[:lab.slot_count], lab.slots[:lab.slot_count])
		}
	}
}

// Marks a technology finished this tick researched, which opens its
// recipes, and returns it for the completion notice.
apply_finished_research :: proc(research: ^Research_State, unlocks: ^Recipe_Unlocks, recipes: Recipe_Registry) -> (technology: int, finished: bool) {
	if !research.finished {
		return NO_TECHNOLOGY, false
	}
	research.finished = false
	mark_technology_researched(unlocks, recipes, research.finished_technology)
	return research.finished_technology, true
}

lab_progress_fraction :: proc(lab: Lab, machine: Machine, research: Research_State, technologies: Technology_Registry, tick_rate: int) -> f32 {
	if !lab_unit_is_current(lab, research) {
		return 0
	}
	technology := technologies.technologies[research.technology]
	return f32(lab.progress_ticks) / f32(technology_unit_ticks(technology, lab_speed_percent(machine, research, technologies), tick_rate))
}

research_progress_fraction :: proc(research: Research_State, technologies: Technology_Registry) -> f32 {
	if !research.queued {
		return 0
	}
	return f32(research.units_done) / f32(queued_research_cost(research, technologies))
}

// Each lab slot takes only its science pack. In the temp allocator.
lab_slot_filters :: proc(lab_packs: []Item_Id, slot_count: int) -> []Slot_Filter {
	filters := make([]Slot_Filter, slot_count, context.temp_allocator)
	for &filter, index in filters {
		filter = {kind = .Item, item = lab_packs[index]}
	}
	return filters
}
