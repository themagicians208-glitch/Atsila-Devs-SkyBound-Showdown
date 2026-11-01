extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
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
	assert(world.find_children("FrostSlime", "Node3D", true, false).size() > 0, "Frost Slimes must spawn")
	assert(world.find_children("FrostWolf", "Node3D", true, false).size() > 0, "Frost Wolves must spawn")
	assert(world.find_children("CrystalPhantom", "Node3D", true, false).size() > 0, "Crystal Phantoms must spawn")
	assert(get_nodes_in_group("collectible_coins").size() >= 50, "Frozen Skies needs at least 50 coins")
	print("LEVEL3 Frozen Skies smoke passed: coins=", get_nodes_in_group("collectible_coins").size())
	quit()

