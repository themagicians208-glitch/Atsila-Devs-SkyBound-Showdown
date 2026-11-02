extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	set_meta("level_number", 5)
	set_meta("resume_save", false)
	var packed: PackedScene = load("res://scenes/main.tscn")
	var instance: Node = packed.instantiate()
	root.add_child(instance)
	await process_frame
	var world: Node = instance.get_node("World")
	var boss: Node = world.get_node_or_null("Malakar")
	assert(instance.get("current_level") == 5, "Level 5 must be active")
	assert(boss != null, "Malakar must spawn in Level 5")
	assert(world.find_children("GateApproach_*", "Node3D", true, false).size() == 8, "fortress approach must spawn")
	assert(world.find_children("IslandLoopPlatform_*", "Node3D", true, false).size() == 64, "island loop must spawn")
	assert(world.find_children("IslandRaccoon_*", "Node3D", true, false).size() == 7, "island wildlife must spawn")
	assert(world.find_children("EnergyConduit_*", "Node3D", true, false).size() == 3, "three conduits must spawn")
	assert(instance.get("gates").size() == 3, "three fortress gates must spawn")
	assert(instance.get_node("Player").global_position.z < -40.0, "player must arrive on Malakar's island")
	assert(not bool(boss.get("encounter_started")), "Malakar must wait for the throne trigger")
	instance.call("_on_finish_body_entered", instance.get_node("Player"))
	assert(bool(boss.get("encounter_started")), "reaching the throne must start Malakar's encounter")
	boss.emit_signal("encounter_completed")
	assert(bool(instance.get("fortress_boss_complete")), "Malakar completion must unlock victory")
	assert(instance.get_node("HUD").victory_overlay.visible, "Level 5 victory screen must open after Malakar")
	print("LEVEL5 Malakar's Fortress smoke passed")
	quit()
