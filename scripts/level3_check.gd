extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# Smoke tests must start from a known progression state, not a developer save.
	get_root().get_node("Progress").clear()
	set_meta("level_number", 3)
	var packed: PackedScene = load("res://scenes/main.tscn")
	assert(packed != null, "main scene must load")
	var instance: Node = packed.instantiate()
	root.add_child(instance)
	await process_frame
	assert(instance.get("current_level") == 3, "level 3 must be selected")
	assert(instance.get("frozen_skies") != null, "Frozen Skies builder must be active")
	var world: Node = instance.get_node("World")
	assert(world.get_node_or_null("FrostTitan") != null, "Frost Titan must spawn")
	assert(world.get_node_or_null("ThirdFragmentChest") != null, "Third Fragment chest must spawn")
	assert(instance.get("frozen_skies").mechanisms.size() == 3, "three frozen mechanisms must spawn")
	assert(instance.get("frozen_skies").region_names.size() == 6, "Frozen Skies needs six named regions")
	assert(instance.get("frozen_skies").region_name_for_checkpoint(38) == "Frost Titan's Sanctuary", "boss region must be named")
	var crystal_puzzle: Node = world.get_node("CrystalLightPuzzle")
	assert(not crystal_puzzle.is_solved, "crystal light puzzle starts unsolved")
	assert(world.find_children("FrostSlime", "Node3D", true, false).size() > 0, "Frost Slimes must spawn")
	assert(world.find_children("FrostWolf", "Node3D", true, false).size() > 0, "Frost Wolves must spawn")
	assert(world.find_children("CrystalPhantom", "Node3D", true, false).size() > 0, "Crystal Phantoms must spawn")
	assert(world.find_children("MovingIcePlatform*", "Node3D", true, false).size() >= 5, "Frozen Skies needs moving ice platforms")
	assert(world.find_children("UnstableIce_*", "Node3D", true, false).size() == 4, "Frozen Lake needs unstable ice")
	assert(get_nodes_in_group("collectible_coins").size() >= 50, "Frozen Skies needs at least 50 coins")
	var player: Node = instance.get_node("Player")
	var crystals: Array = crystal_puzzle.get("_crystals")
	for index in crystals.size():
		player.global_position = crystals[index].global_position
		for turn in range(index + 1):
			assert(crystal_puzzle.try_interact(player), "crystal interaction must be usable")
	assert(crystal_puzzle.is_solved, "crystal light puzzle must solve")
	var wolf: Node = world.find_children("FrostWolf", "Node3D", true, false)[0]
	assert(is_equal_approx(wolf._movement_speed(player), float(player.movement_speed) * 1.10), "Frost Wolf must be 110% of player speed")
	var slime: Node = world.find_children("FrostSlime", "Node3D", true, false)[0]
	assert(is_equal_approx(slime._movement_speed(player), float(player.movement_speed) * 0.50), "Frost Slime must be 50% of player speed")
	var titan: Node = world.get_node("FrostTitan")
	assert(titan.locked, "Frost Titan must be locked behind the frozen seals")
	for mechanism in instance.get("frozen_skies").mechanisms:
		mechanism.activate()
	assert(not titan.locked, "Frost Titan must unlock after all frozen seals")
	titan.take_hit(10, player.global_position)
	assert(titan.phase == 2, "Frost Titan must enter phase 2")
	titan.take_hit(12, player.global_position)
	assert(titan.phase == 3, "Frost Titan must enter phase 3")
	titan.take_hit(8, player.global_position)
	assert(titan.phase == 4, "Frost Titan must enter the final phase")
	print("LEVEL3 Frozen Skies smoke passed: coins=", get_nodes_in_group("collectible_coins").size())
	quit()

