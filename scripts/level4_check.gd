extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	get_root().get_node("Progress").clear()
	get_root().get_node("Progress").recover_fragment()
	get_root().get_node("Progress").recover_second_fragment()
	get_root().get_node("Progress").recover_third_fragment()
	set_meta("level_number", 4)
	var packed: PackedScene = load("res://scenes/main.tscn")
	assert(packed != null, "main scene must load")
	var instance: Node = packed.instantiate()
	root.add_child(instance)
	await process_frame
	assert(instance.get("current_level") == 4, "level 4 must be selected")
	assert(instance.get("ember_heights") != null, "Ember Heights builder must be active")
	var world: Node = instance.get_node("World")
	assert(world.get_node_or_null("EmberDragon") != null, "Ember Dragon must spawn")
	assert(world.get_node_or_null("FourthFragmentChest") != null, "Fourth Fragment chest must spawn")
	assert(get_nodes_in_group("collectible_coins").size() > 60, "Ember Heights needs more than 60 coins")
	get_root().get_node("Progress").clear()
	print("LEVEL4 Ember Heights smoke passed: coins=", get_nodes_in_group("collectible_coins").size())
	quit()
