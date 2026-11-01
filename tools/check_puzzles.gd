extends Node

## Walks the island's puzzles the way a player does: find the switch, press the
## interact key, watch the gate open; walk into the crystal, carry it to the
## pedestal, press interact again, and watch the bridge rise. Also checks that the
## island is properly shut before either of them is solved, so the puzzles are not
## decoration.
##
## Run: godot --headless --path . tools/check_puzzles.tscn

var _problems: Array[String] = []


func _ready() -> void:
	get_tree().set_meta("level_number", 1)
	get_tree().set_meta("local_coop", false)
	get_tree().set_meta("online", false)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.8).timeout

	var player: CharacterBody3D = main.get("player")
	var island: ForgottenIsland = main.get("island")
	var gate: IslandGate = island.get_node_or_null("AncientGate")
	var switch_node: IslandSwitch = island.get_node_or_null("AncientSwitch")
	var crystal: IslandCrystal = island.find_crystal()
	var pedestal: CrystalPedestal = island.get_node_or_null("CrystalPedestal")

	for named in [["switch", switch_node], ["gate", gate], ["crystal", crystal], ["pedestal", pedestal]]:
		if named[1] == null:
			_problems.append("the island has no %s" % named[0])
	if not _problems.is_empty():
		_report()
		return

	# --- Before anything is solved ------------------------------------------
	var gate_shape: CollisionShape3D = gate.find_children("*", "CollisionShape3D", true, false)[0]
	print("as found: gate open %s, collision disabled %s, crystal carried %s" % [
		gate.opened, gate_shape.disabled, crystal.carried])
	if gate.opened or gate_shape.disabled:
		_problems.append("the gate starts open")
	if crystal.carried:
		_problems.append("the crystal starts carried")

	var planks_hidden := true
	for node in island.get_children():
		if node.name.begins_with("Bridge_hidden_crystal"):
			var plank_shape: CollisionShape3D = (node as Node3D).find_children("*", "CollisionShape3D", true, false)[0]
			if (node as Node3D).visible or not plank_shape.disabled:
				planks_hidden = false
	print("as found: bridge planks hidden %s" % planks_hidden)
	if not planks_hidden:
		_problems.append("the bridge is already there before the crystal is placed")

	# --- Puzzle 1: the switch ------------------------------------------------
	player.global_position = switch_node.global_position + Vector3(0.0, 0.6, 1.6)
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	_press_interact()
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("after pressing interact at the switch: solved %s, gate open %s, collision disabled %s" % [
		island.is_puzzle_solved("ancient_switch"), gate.opened, gate_shape.disabled])
	if not island.is_puzzle_solved("ancient_switch"):
		_problems.append("pressing interact at the switch did nothing")
	if not gate.opened:
		_problems.append("the gate did not open when its switch was pressed")

	# --- Puzzle 2: the crystal, hidden in the cave --------------------------
	player.global_position = crystal.global_position + Vector3(0.4, 0.6, 0.4)
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("walking into the crystal: carried %s" % crystal.carried)
	if not crystal.carried:
		_problems.append("walking into the hidden crystal did not pick it up")

	# Carrying it to the pedestal and pressing interact there.
	player.global_position = pedestal.global_position + Vector3(0.0, 0.6, 1.6)
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("crystal rides above the player at %s" % crystal.global_position)
	if crystal.global_position.distance_to(player.global_position + Vector3(0.0, 1.5, 0.0)) > 1.0:
		_problems.append("the carried crystal does not follow the player")
	_press_interact()
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().create_timer(1.2).timeout

	var planks_up := 0
	var planks_solid := 0
	for node in island.get_children():
		if node.name.begins_with("Bridge_hidden_crystal"):
			var plank := node as Node3D
			if plank.visible:
				planks_up += 1
			var shape: CollisionShape3D = plank.find_children("*", "CollisionShape3D", true, false)[0]
			if not shape.disabled:
				planks_solid += 1
	print("after placing the crystal: pedestal filled %s, solved %s, planks up %d, planks solid %d" % [
		pedestal.done, island.is_puzzle_solved("hidden_crystal"), planks_up, planks_solid])
	if not pedestal.done:
		_problems.append("the pedestal did not accept the crystal")
	if planks_up < 3 or planks_solid < 3:
		_problems.append("the bridge did not rise (up %d, solid %d of 3)" % [planks_up, planks_solid])

	# --- The way on is now open --------------------------------------------
	var closed := island.is_puzzle_solved("ancient_switch") and island.is_puzzle_solved("hidden_crystal")
	print("both puzzles solved: %s" % closed)

	# --- Puzzle 4: the three nature seals -----------------------------------
	var seals: Array = []
	for node in island.get_children():
		if node is NatureSeal:
			seals.append(node as NatureSeal)
	var grove: NatureSeal = island.get_node_or_null("Seal_grove")
	var terrace: NatureSeal = island.get_node_or_null("Seal_terrace")
	var summit: NatureSeal = island.get_node_or_null("Seal_summit")
	print("seals: %d (%s)" % [seals.size(), [grove != null, terrace != null, summit != null]])
	if seals.size() != 3 or grove == null or terrace == null or summit == null:
		_problems.append("the island does not have its three seals")
	else:
		for seal in seals:
			if seal.awakened:
				_problems.append("%s starts already awake" % seal.name)

		# The grove seal is warded while a Shadow Slime is alive near it.
		var guard: ShadowSlime = null
		for node in get_tree().get_nodes_in_group("shadow_slimes"):
			var slime := node as ShadowSlime
			if slime.global_position.distance_to(grove.global_position) <= float(grove.get("ward_range")):
				guard = slime
		print("grove seal warded by %s, reason: '%s'" % [
			guard.name if guard != null else "nothing", grove.blocking_reason()])
		if guard == null:
			_problems.append("no Shadow Slime is actually guarding the grove seal")
		else:
			player.global_position = grove.global_position + Vector3(0.0, 0.6, 1.8)
			player.velocity = Vector3.ZERO
			await get_tree().physics_frame
			await get_tree().physics_frame
			_press_interact()
			await get_tree().physics_frame
			if grove.awakened:
				_problems.append("the grove seal opened while its slime was still alive")
			# Kill the guard: the seal should accept now.
			guard.call("take_hit", 99, guard.global_position + Vector3(0.0, 0.0, -1.0))
			await get_tree().create_timer(1.0).timeout
			_press_interact()
			await get_tree().physics_frame
			print("after the guard is destroyed: grove seal awake %s" % grove.awakened)
			if not grove.awakened:
				_problems.append("the grove seal still refuses with its guardian gone")

		# The terrace seal waits for the switch hidden behind the waterfall.
		player.global_position = terrace.global_position + Vector3(0.0, 0.6, 1.8)
		player.velocity = Vector3.ZERO
		await get_tree().physics_frame
		await get_tree().physics_frame
		_press_interact()
		await get_tree().physics_frame
		print("terrace seal before the hidden switch: awake %s, reason: '%s'" % [
			terrace.awakened, terrace.blocking_reason()])
		if terrace.awakened:
			_problems.append("the terrace seal opened before its hidden switch was thrown")
		var hidden: IslandSwitch = island.get_node_or_null("HiddenSwitch")
		if hidden == null:
			_problems.append("the hidden switch behind the waterfall is missing")
		else:
			hidden.activate()
			await get_tree().physics_frame
			_press_interact()
			await get_tree().physics_frame
			print("after the hidden switch: terrace seal awake %s" % terrace.awakened)
			if not terrace.awakened:
				_problems.append("the terrace seal did not open after its switch was thrown")

		# The summit seal: the climb is the challenge, so it opens on arrival.
		player.global_position = summit.global_position + Vector3(0.0, 0.6, 1.8)
		player.velocity = Vector3.ZERO
		await get_tree().physics_frame
		await get_tree().physics_frame
		_press_interact()
		await get_tree().physics_frame
		print("summit seal awake %s, seals lit %d" % [summit.awakened, island.seals_awakened()])
		if not summit.awakened:
			_problems.append("the summit seal did not open when the player reached it")

		var ruins_gate: IslandGate = island.get_node_or_null("RuinsGate")
		var ruins_shape: CollisionShape3D = null
		if ruins_gate != null:
			ruins_shape = ruins_gate.find_children("*", "CollisionShape3D", true, false)[0]
		print("after all three seals: nature_seals solved %s, ruins gate open %s, collision disabled %s" % [
			island.is_puzzle_solved("nature_seals"),
			ruins_gate.opened if ruins_gate != null else false,
			ruins_shape.disabled if ruins_shape != null else false])
		if not island.is_puzzle_solved("nature_seals"):
			_problems.append("three lit seals did not open the ruins")
		if ruins_gate == null or not ruins_gate.opened or not ruins_shape.disabled:
			_problems.append("the ruins gate did not open with all three seals lit")

	# --- Puzzle 5: the ancient ruins ----------------------------------------
	var stations: Array = []
	for node in island.get_children():
		if node is RuinSymbol:
			stations.append(node as RuinSymbol)
	stations.sort_custom(func(a, b): return a.global_position.x < b.global_position.x)
	var chamber: IslandGate = island.get_node_or_null("ChamberGate")
	print("ruin stations: %d, chamber gate %s" % [stations.size(), chamber != null])
	if stations.size() != 3 or chamber == null:
		_problems.append("the ruins puzzle is missing stations or its chamber gate")
	else:
		for station in stations:
			if station.is_charged:
				_problems.append("%s starts charged" % station.name)
		if chamber.opened:
			_problems.append("the chamber gate starts open")

		# The clue has to name the right shape for the right station, or the puzzle
	# is guesswork: read the markers' pips against what each station wants.
	var clues: Array = []
	for node in island.get_children():
		if node.has_meta("station"):
			clues.append(node)
	clues.sort_custom(func(a, b): return int(a.get_meta("station")) < int(b.get_meta("station")))
	var clue_lines: Array = []
	for clue in clues:
		clue_lines.append("%d -> %s" % [int(clue.get_meta("station")) + 1,
			RuinSymbol.SHAPE_NAMES[int(clue.get_meta("shape"))]])
	print("clue markers: %d %s" % [clues.size(), clue_lines])
	if clues.size() != 3:
		_problems.append("the ruins clue is not fully placed")
	else:
		for clue in clues:
			var target := int(clue.get_meta("station"))
			if target >= stations.size() or int(clue.get_meta("shape")) != stations[target].required:
				_problems.append("a clue marker names the wrong shape for its station")

	# A station with the wrong symbol refuses its plate.
		var first: RuinSymbol = stations[0]
		var wrong := (first.required + 1) % 3
		first.set_symbol(wrong)
		player.global_position = first.global_position + Vector3(0.0, 0.7, 1.9)
		player.velocity = Vector3.ZERO
		await get_tree().physics_frame
		await get_tree().physics_frame
		print("wrong symbol (%s, needs %s): charged %s" % [
			first.shape_name(), first.required_name(), first.is_charged])
		if first.is_charged:
			_problems.append("a plate charged with the wrong symbol on its pillar")

		# Turn it the right way and stand on it again.
		while not first.matches():
			first.turn()
		await get_tree().physics_frame
		await get_tree().physics_frame
		print("right symbol (%s): charged %s after stepping on the plate" % [
			first.shape_name(), first.is_charged])
		if not first.is_charged:
			_problems.append("the plate did not charge with the right symbol")

		# Now the other two, the same way a player would.
		for station in stations:
			if station.is_charged:
				continue
			while not station.matches():
				station.turn()
			player.global_position = station.global_position + Vector3(0.0, 0.7, 1.9)
			player.velocity = Vector3.ZERO
			await get_tree().physics_frame
			await get_tree().physics_frame
		print("stations charged %d of %d, ruins_sequence solved %s, chamber gate open %s" % [
			island.ruin_stations_charged(), stations.size(),
			island.is_puzzle_solved("ruins_sequence"), chamber.opened])
		if island.ruin_stations_charged() != stations.size():
			_problems.append("not every station charged")
		if not island.is_puzzle_solved("ruins_sequence"):
			_problems.append("three charged stations did not solve the ruins")
		if not chamber.opened:
			_problems.append("the chamber gate did not open with the ruins solved")

	# --- Puzzle 3: the vanishing crossing ----------------------------------
	# Two things have to hold for the crossing to be a puzzle rather than a lottery:
	# neighbours are never gone at the same moment, and every stone stands long
	# enough to land on and jump off again.
	var stones: Array = []
	for node in island.get_children():
		if node is VanishingPlatform:
			stones.append(node as VanishingPlatform)
	stones.sort_custom(func(a, b): return a.global_position.z < b.global_position.z)
	print("vanishing stones: %d" % stones.size())
	if stones.size() < 4:
		_problems.append("the vanishing crossing has only %d stones" % stones.size())
	for stone in stones:
		if stone.solid_fraction() < 0.55:
			_problems.append("%s is only standing %.0f%% of the time" % [
				stone.name, stone.solid_fraction() * 100.0])
	var unfair := 0
	var steps := 0
	while steps < 140:
		steps += 1
		await get_tree().process_frame
		for i in range(stones.size() - 1):
			if not stones[i].solid and not stones[i + 1].solid:
				unfair += 1
				break
	print("over %d sampled moments, neighbours both gone: %d" % [steps, unfair])
	if unfair > 0:
		_problems.append("two neighbouring stones were gone at the same moment %d times" % unfair)
	var standing := 0
	for stone in stones:
		if stone.solid:
			standing += 1
	print("stones standing right now: %d of %d" % [standing, stones.size()])
	if standing == 0:
		_problems.append("every vanishing stone was gone at once")

	_report()


## A real interact keypress, delivered the way the game receives one.
func _press_interact() -> void:
	for action in ["interact", "p1_interact", "p2_interact"]:
		if not InputMap.has_action(action):
			continue
		var pressed := InputEventAction.new()
		pressed.action = action
		pressed.pressed = true
		Input.parse_input_event(pressed)
		var released := InputEventAction.new()
		released.action = action
		released.pressed = false
		Input.parse_input_event(released)


func _report() -> void:
	print("")
	if _problems.is_empty():
		print("PUZZLES OK - switch opens the gate, the crystal raises the bridge, and both start shut")
	else:
		print("PUZZLE PROBLEMS (%d):" % _problems.size())
		for problem in _problems:
			print("  - " + problem)
	get_tree().quit()