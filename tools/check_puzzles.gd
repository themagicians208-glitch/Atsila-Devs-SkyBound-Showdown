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