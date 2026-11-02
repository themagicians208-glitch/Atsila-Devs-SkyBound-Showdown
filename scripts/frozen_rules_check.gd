extends SceneTree

## Focused check for Frozen Skies' dynamic rule-changing puzzles: the initial
## rules, the warning, the actual mechanic change, that every puzzle is still
## solvable afterwards, that a failure resets cleanly, and that the stage of each
## puzzle survives a save/reload.
##
## Every puzzle is driven through the real API (interactions, platform landings,
## enemy kills) - nothing is poked into the solved state directly.

const LEVEL := 3

var _notices: Array[String] = []
var _warnings := 0
var _instance: Node
var _fs: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func():
		push_error("FROZEN RULES check timed out")
		quit(1))
	var progress: Node = get_root().get_node("Progress")
	progress.config_path = "user://frozen_rules_%d.cfg" % OS.get_process_id()
	progress.clear()
	progress.recover_fragment()
	progress.recover_second_fragment()
	# The Ice Shield is the first seal's reward and the lake is five regions later,
	# so the player taking the lake on always has it.
	progress.unlock_ice_shield()
	await _build_level()
	var fs: Node = _fs
	var rules: Dictionary = fs.get("rule_puzzles")
	_assert(rules.size() == 8, "eight rule-changing puzzles must be registered")

	# Every puzzle reports its own rules, and every rule change announces itself.
	for id in rules.keys():
		var shift: Node = (rules[id] as Node).get("rule_shift")
		shift.connect("notice", _on_notice)
		shift.connect("warning_started", _on_warning)
		_assert(str(shift.call("state_name")) == "INITIAL_STATE", "%s must start on its first rules" % id)
		_assert(int(shift.get("stage")) == 0, "%s must start at stage 0" % id)

	await _check_frozen_switch(rules)
	await _check_valley(rules)
	await _check_lake(rules)
	await _check_fortress(rules)
	await _check_seal_one(rules)
	await _check_seal_three(rules)
	await _check_titan_arena()

	# The engine's own book-keeping: warnings were visible and audible, and the
	# player-visible notice appeared for the changes.
	_assert(_warnings >= 6, "every rule change must start a visible warning window")
	_assert(_notices.size() > 0, "rule changes must say something to the player")
	var saw_warning_text := false
	var saw_change_text := false
	for line in _notices:
		if line.begins_with("WARNING: THE ICE IS SHIFTING"):
			saw_warning_text = true
		if line.contains("REVERS") or line.contains("SHIFTING") or line.contains("ALTERED") \
				or line.contains("DESTABILIZED") or line.contains("MELTING") or line.contains("FROZEN"):
			saw_change_text = true
	_assert(saw_warning_text, "the warning must be spelled out for the player")
	_assert(saw_change_text, "the new rule must be spelled out for the player")

	await _check_save_reload()
	print("FROZEN RULES OK: warnings=%d notices=%d" % [_warnings, _notices.size()])
	# Let the level go before the engine tears the process down: leaving a live
	# level with signals wired into this SceneTree script behind makes shutdown
	# unstable. (The level was rebuilt during the save check, so look up the
	# puzzles that exist right now, not the first set.)
	var live_rules: Dictionary = _fs.get("rule_puzzles")
	for id in live_rules.keys():
		var shift: Node = (live_rules[id] as Node).get("rule_shift")
		if shift.is_connected("notice", Callable(self, "_on_notice")):
			shift.disconnect("notice", Callable(self, "_on_notice"))
		if shift.is_connected("warning_started", Callable(self, "_on_warning")):
			shift.disconnect("warning_started", Callable(self, "_on_warning"))
	_instance.queue_free()
	await process_frame
	await process_frame
	progress.clear()
	quit()


func _on_notice(text: String, _tone: String) -> void:
	_notices.append(text)


func _on_warning(_puzzle_name: String) -> void:
	_warnings += 1


func _build_level() -> void:
	set_meta("level_number", LEVEL)
	_instance = load("res://scenes/main.tscn").instantiate()
	root.add_child(_instance)
	await process_frame
	await process_frame
	_fs = _instance.get("frozen_skies")
	_assert(_fs != null, "Frozen Skies must build")
	_assert((_fs.get("mechanisms") as Array).size() == 3, "Frozen Skies keeps its three frozen seals")


func _player() -> Node:
	return _instance.get("player")


## A teleported test player can fall off a puzzle island the way a real player can.
## Bring them back the way the level does, then hand them their vitals.
func _revive_player() -> void:
	var player: Node = _player()
	if bool(player.get("is_dead")):
		_instance.call("respawn_player", player)
	player.call("reset_vitals")


func _shift(site: Node) -> Node:
	return site.get("rule_shift")


func _warning_wait(site: Node) -> void:
	await create_timer(float(_shift(site).get("warning_seconds")) + 0.5).timeout


# --- Puzzle 1: The Frozen Switch ---------------------------------------------
func _check_frozen_switch(rules: Dictionary) -> void:
	var site: Node = rules["frozen_switch"]
	var shift: Node = _shift(site)
	var player: Node = _player()
	# A wrong switch resets the puzzle without silently solving anything.
	player.global_position = (site.get("switches") as Array)[1].global_position
	_assert(_fs.call("try_activate_nearby", player), "switches must be interactable")
	_assert(str(shift.call("state_name")) == "FAILED" or int(shift.get("steps_done")) == 0,
			"a wrong switch must roll the puzzle back")
	_assert(not site.is_solved(), "a failed attempt must not solve the puzzle")
	# Right order: I, II -> the rules change -> crystal -> III, I.
	for index in [0, 1]:
		player.global_position = (site.get("switches") as Array)[index].global_position
		_assert(_fs.call("try_activate_nearby", player), "switch %d must be usable" % index)
	_assert(str(shift.call("state_name")) == "RULE_CHANGE_WARNING", "the second switch must start the warning")
	_assert(not bool(shift.get("shifted")), "nothing may change during the warning")
	_assert(not site.is_solved(), "the puzzle must not be finished by the warning")
	await _warning_wait(site)
	_assert(int(shift.get("stage")) == 1, "the Frozen Switch must reach stage 1")
	_assert(bool(site.get("_dead_switch")), "the first switch must go dead")
	_assert(bool(site.get("_crystal_visual").visible), "the crystal must be revealed")
	_assert(site.get("_order") == [2, 0], "the required order must change")
	# Switch I refuses until the crystal is taken; III then completes the run.
	player.global_position = (site.get("switches") as Array)[0].global_position
	_assert(_fs.call("try_activate_nearby", player), "dead switch interaction must be handled")
	_assert(not (site.get("_lit") as Array)[0], "a dead switch must not light")
	player.global_position = (site.get("_crystal") as Node3D).global_position
	_assert(_fs.call("try_activate_nearby", player), "the revealed crystal must be takable")
	_assert(not bool(site.get("_dead_switch")), "the crystal must restore switch I")
	for index in [2, 0]:
		player.global_position = (site.get("switches") as Array)[index].global_position
		_assert(_fs.call("try_activate_nearby", player), "switch %d must be usable after the change" % index)
	_assert(site.is_solved(), "the Frozen Switch must be solvable under its new rules")
	_assert(bool(shift.get("finished")), "finishing the puzzle must complete its RuleShift")


# --- Puzzle 2: Slippery Ice Valley -------------------------------------------
func _check_valley(rules: Dictionary) -> void:
	var site: Node = rules["ice_wind_valley"]
	var shift: Node = _shift(site)
	var player: Node = _player()
	var platforms: Array = site.get("platforms")
	player.global_position = platforms[0].global_position
	await create_timer(0.2).timeout
	_assert(int(shift.get("steps_done")) >= 1, "standing on the first platform must count as progress")
	_assert(not bool(shift.get("shifted")), "the wind must not change on the first platform")
	player.global_position = platforms[2].global_position
	await create_timer(0.2).timeout
	_assert(str(shift.call("state_name")) == "RULE_CHANGE_WARNING", "halfway across must start the warning")
	await _warning_wait(site)
	_assert(bool(shift.get("shifted")), "the wind must turn")
	var offsets: Array = site.get("_offsets")
	_assert(float(offsets[0]) < 0.0 and float(offsets[1]) > 0.0, "two platforms must reverse their patrol")
	var speeds: Array = site.get("_speeds")
	_assert(float(speeds[2]) == 0.0, "one platform must freeze solid")
	var slicks: Array = site.get("_slick_zones")
	_assert(bool((slicks[2] as Node3D).visible) and bool((slicks[4] as Node3D).visible), "two platforms must turn slick")
	var timers: Array = site.get("_crumble_timers")
	_assert(float(timers[0]) > 0.0, "the outer platforms must start cracking")
	# The crossing is still completable.
	player.global_position = site.island_position()
	await create_timer(0.3).timeout
	_assert(site.is_solved(), "the valley must still be crossable after the change")


# --- Puzzle 4: The Frozen Lake (two rule changes) ----------------------------
func _check_lake(rules: Dictionary) -> void:
	var site: Node = rules["frozen_lake"]
	var shift: Node = _shift(site)
	var player: Node = _player()
	_assert(int(shift.get("shift_triggers").size()) == 2, "the lake must change its rules twice")
	# Stage one: the switch melts the lake.
	player.global_position = (site.get("cycle_switch") as Node3D).global_position
	_assert(_fs.call("try_activate_nearby", player), "the lake switch must be usable")
	await _warning_wait(site)
	_assert(int(shift.get("stage")) == 1, "the lake must reach its melting stage")
	_assert(bool((site.get("_energy_mechanism") as Node3D).visible), "melting must reveal the energy mechanism")
	var drift: Array = site.get("_drift")
	var drifting := false
	for value in drift:
		if absf(float(value)) > 0.5:
			drifting = true
	_assert(drifting, "some blocks must come loose and drift while the lake melts")
	# The mechanism will not wake without the Ice Shield.
	player.global_position = (site.get("_energy_mechanism") as Node3D).global_position
	_assert(_fs.call("try_activate_nearby", player), "the mechanism must be interactable")
	_assert(int(shift.get("stage")) == 1, "the mechanism must refuse to wake without the Ice Shield")
	player.call("reset_vitals")
	_revive_player()
	player.call("_activate_ice_shield")
	_assert(bool(player.get("ice_shield_active")), "the Ice Shield must be usable")
	# A respawn puts the player back at the checkpoint, so walk back to the
	# mechanism before using it.
	player.global_position = (site.get("_energy_mechanism") as Node3D).global_position
	_assert(_fs.call("try_activate_nearby", player), "the mechanism must be usable with the shield up")
	await _warning_wait(site)
	_assert(int(shift.get("stage")) == 2, "the lake must reach its re-freezing stage")
	var fixed := true
	for value in site.get("_drift"):
		if absf(float(value)) > 0.01:
			fixed = false
	_assert(fixed, "the drifting blocks must lock in place when the lake re-freezes")
	var slicks: Array = site.get("_slick_zones")
	var slick_count := 0
	for zone in slicks:
		if bool((zone as Node3D).visible):
			slick_count += 1
	_assert(slick_count == 2, "two re-frozen blocks must turn slippery")
	# Solvability: neighbours in the wave are never submerged together, so a route
	# always exists at every moment of the cycle.
	var worst := _lake_route_gap(site)
	_assert(worst <= 1, "the freezing wave must always leave a route (worst run of outages: %d)" % worst)
	player.global_position = site.far_shore_position()
	await create_timer(0.3).timeout
	_assert(site.is_solved(), "the lake must be crossable after both rule changes")


## Walks the lake's own cycle and reports the longest run of consecutive
## submerged blocks - 1 means a route always existed.
func _lake_route_gap(site: Node) -> int:
	var runs: Array[int] = []
	var current := 0
	var states: Array = site.get("_floe_state")
	for step in 400:
		site.call("_process", 0.05)
		for index in states.size():
			if int(states[index]) == 2:
				current += 1
			else:
				if current > 0:
					runs.append(current)
				current = 0
		if current > 0:
			runs.append(current)
			current = 0
	var worst := 0
	for value in runs:
		if value > worst:
			worst = value
	return worst


# --- Puzzle 5: The Shattered Ice Fortress (two rule changes) -----------------
func _check_fortress(rules: Dictionary) -> void:
	var site: Node = rules["fortress_shift"]
	var shift: Node = _shift(site)
	var player: Node = _player()
	var mechanisms: Array = site.get("mechanisms")
	_assert(mechanisms.size() == 3, "the fortress must need three mechanisms")
	var bridge_rate_before := float(_fs.get("_bridge_rate"))
	for index in [0, 1]:
		player.global_position = (mechanisms[index] as Node3D).global_position
		_assert(_fs.call("try_activate_nearby", player), "fortress mechanism %d must be usable" % index)
	_assert(str(shift.call("state_name")) == "RULE_CHANGE_WARNING", "the second mechanism must start the warning")
	await _warning_wait(site)
	_assert(int(shift.get("stage")) == 1, "the fortress must reach its structural change")
	_assert(bool((site.get("blocker") as Node3D).visible), "the old corridor must be walled off")
	_assert(bool((site.get("gravity_zone") as Area3D).get("monitoring")), "the marked gravity section must wake")
	_assert(not is_equal_approx(float(_fs.get("_bridge_rate")), bridge_rate_before),
			"the fortress bridges must rotate the other way")
	var mirror_platforms: Array = site.get("mirror_platforms")
	var in_group := 0
	for platform in mirror_platforms:
		if (platform as Node3D).is_in_group("mirror_dimension"):
			in_group += 1
	_assert(in_group == mirror_platforms.size(), "the mirror route must switch on")
	_assert(int(_instance.get("dimension_shifts_left")) >= 1, "the mirror route must come with shifts to spend")
	# Stage two: walking the storm walk starts the frost storm.
	player.global_position = site.storm_walk_position()
	await create_timer(0.3).timeout
	_assert(str(shift.call("state_name")) == "RULE_CHANGE_WARNING", "the storm walk must start the second warning")
	await _warning_wait(site)
	_assert(int(shift.get("stage")) == 2, "the fortress must reach its storm stage")
	var timers: Array = site.get("storm_timers")
	var live := false
	for value in timers:
		if float(value) > 0.0:
			live = true
	_assert(live, "the storm must start pulling platforms in and out")
	player.global_position = (mechanisms[2] as Node3D).global_position
	_assert(_fs.call("try_activate_nearby", player), "mechanism C must be usable through the storm")
	_assert(site.is_solved(), "the fortress must be solvable after both changes")
	_assert(bool((site.get("fortress_gate") as Node).get("opened")), "finishing the fortress must open its gate")


# --- Seal I: moving platforms reverse midway ---------------------------------
func _check_seal_one(rules: Dictionary) -> void:
	var site: Node = rules["seal_one"]
	var shift: Node = _shift(site)
	var player: Node = _player()
	var platforms: Array = site.get("platforms")
	var before: Array = (site.get("_offsets") as Array).duplicate()
	player.global_position = platforms[1].global_position
	await create_timer(0.25).timeout
	_assert(str(shift.call("state_name")) == "RULE_CHANGE_WARNING", "Seal I must warn before reversing")
	await _warning_wait(site)
	var after: Array = site.get("_offsets")
	var reversed_count := 0
	for index in min(before.size(), after.size()):
		# The patrols are direction vectors: a reversed platform points the other way.
		if (before[index] as Vector3).dot(after[index] as Vector3) < 0.0:
			reversed_count += 1
	_assert(reversed_count == before.size(), "every platform in Seal I must swap direction")
	player.global_position = site.far_side_position()
	await create_timer(0.3).timeout
	_assert(site.is_solved(), "Seal I must still be completable")


# --- Seal III: the arena ground shifts mid-fight ------------------------------
func _check_seal_three(rules: Dictionary) -> void:
	var site: Node = rules["seal_three"]
	var shift: Node = _shift(site)
	var player: Node = _player()
	player.global_position = (_fs.get("mechanisms") as Array)[2].global_position
	await create_timer(0.3).timeout
	_assert(int(shift.get("steps_done")) >= 1, "walking into the arena must start the encounter")
	var guardian: Node = null
	for enemy in get_nodes_in_group("enemies"):
		if str((enemy.get_script() as Script).resource_path).ends_with("frozen_enemy.gd"):
			guardian = enemy
			break
	_assert(guardian != null, "the frozen guardians must be there to fight")
	guardian.call("take_hit", 999, player.global_position)
	await create_timer(0.3).timeout
	_assert(str(shift.call("state_name")) == "RULE_CHANGE_WARNING", "the first fallen guardian must change the arena rules")
	await _warning_wait(site)
	var timers: Array = site.get("_timers")
	var live := false
	for value in timers:
		if float(value) > 0.0:
			live = true
	_assert(live, "the safe platforms must start fading once a guardian falls")
	for enemy in get_nodes_in_group("enemies"):
		if str((enemy.get_script() as Script).resource_path).ends_with("frozen_enemy.gd"):
			enemy.call("take_hit", 999, player.global_position)
	await create_timer(0.4).timeout
	_assert(site.is_solved(), "Seal III must complete when the guardians are beaten")


# --- Absolute Frost: the arena itself moves ---------------------------------
## The four sanctuary slabs swap slots when they turn, so they have to turn
## together - one slab held back by the player standing on it would land a
## neighbour on top of it, merging two floors into one.
func _check_titan_arena() -> void:
	var slabs: Array = _fs.get("_arena_platforms")
	_assert(slabs.size() == 4, "the sanctuary must have four movable slabs")
	var player: Node = _player()
	_revive_player()
	var before: Array = []
	for slab in slabs:
		before.append((slab as Node3D).global_position)
	# The player is standing on a slab: the whole turn waits.
	player.global_position = (slabs[0] as Node3D).global_position + Vector3(0.0, 1.0, 0.0)
	_fs.call("_shift_arena_platforms")
	await process_frame
	_assert(bool(_fs.get("_arena_reposition_pending")), "the arena must hold its turn while the player is on a slab")
	_assert(_slabs_moved(slabs, before) == 0, "no slab may turn while the player stands on one")
	# Clear of the slabs, all four turn together and stay apart.
	player.global_position = (_fs.get("route") as Array)[0]
	_fs.call("_shift_arena_platforms")
	await process_frame
	_assert(_slabs_moved(slabs, before) == 4, "all four slabs must turn together")
	var closest := INF
	for index in slabs.size():
		for other in range(index + 1, slabs.size()):
			closest = minf(closest, (slabs[index] as Node3D).global_position.distance_to(
					(slabs[other] as Node3D).global_position))
	_assert(closest > 3.0, "turned slabs must not merge with each other (closest %.2f)" % closest)


func _slabs_moved(slabs: Array, before: Array) -> int:
	var moved := 0
	for index in slabs.size():
		if not (slabs[index] as Node3D).global_position.is_equal_approx(before[index]):
			moved += 1
	return moved


# --- Rule state survives a reload -------------------------------------------
func _check_save_reload() -> void:
	var stages_before: Dictionary = {}
	for id in (_fs.get("rule_puzzles") as Dictionary).keys():
		stages_before[id] = int(((_fs.get("rule_puzzles") as Dictionary)[id] as Node).get("rule_shift").get("stage"))
	_instance.queue_free()
	await process_frame
	await process_frame
	await _build_level()
	var restored: Dictionary = _fs.get("rule_puzzles")
	for id in stages_before.keys():
		var stage_now := int((restored[id] as Node).get("rule_shift").get("stage"))
		_assert(stage_now == int(stages_before[id]), "%s must reload on the same rules (stage %d, not %d)" % [id, stages_before[id], stage_now])
	# And the world really is in the re-frozen / stormed state, not just the flag.
	var lake: Node = restored["frozen_lake"]
	var fixed := true
	for value in lake.get("_drift"):
		if absf(float(value)) > 0.01:
			fixed = false
	_assert(fixed, "a reloaded re-frozen lake must keep its blocks locked")
	var fortress: Node = restored["fortress_shift"]
	_assert(bool((fortress.get("gravity_zone") as Area3D).get("monitoring")), "a reloaded fortress must keep its gravity rules")
	var switch_puzzle: Node = restored["frozen_switch"]
	_assert(bool((switch_puzzle.get("rule_shift") as Node).get("finished")), "a solved puzzle must reload as solved")


func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error("FROZEN RULES: " + message)
		print("FROZEN RULES FAILED: ", message)
		quit(1)
		await process_frame
		return